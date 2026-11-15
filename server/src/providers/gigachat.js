// GigaChat (Сбер): text, vision (photo as an uploaded file), JSON via function calling, Kandinsky images.
// Docs: https://developers.sber.ru/docs/ru/gigachat/api/overview
import { randomUUID } from 'node:crypto';
import { config } from '../config.js';
import { ApiError, request, readJSON, readSSE, parseLooseJSON } from '../util.js';

let token = null; // { value, expiresAt (ms) }
let workingBase = null;

async function accessToken() {
  if (token && Date.now() < token.expiresAt - 120_000) return token.value;
  const response = await request(config.gigachat.oauthURL, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${config.gigachat.authKey}`,
      RqUID: randomUUID(),
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/json',
    },
    body: `scope=${encodeURIComponent(config.gigachat.scope)}`,
  }, 30_000);
  const body = await readJSON(response);
  if (!response.ok || !body.access_token) {
    throw new ApiError(502, `GigaChat: не удалось получить доступ (${response.status}). Проверьте GIGACHAT_AUTH_KEY и scope.`);
  }
  // expires_at is documented without units: seconds or milliseconds.
  const raw = Number(body.expires_at) || 0;
  const expiresAt = raw > 1e12 ? raw : raw > 0 ? raw * 1000 : Date.now() + 25 * 60_000;
  token = { value: body.access_token, expiresAt };
  return token.value;
}

/** Calls an API path on the first base URL that answers (the documented host changed over time). */
async function call(path, init, timeoutMs) {
  const bases = workingBase ? [workingBase, ...config.gigachat.bases.filter((b) => b !== workingBase)] : config.gigachat.bases;
  let last;
  for (const base of bases) {
    const auth = await accessToken();
    const response = await request(`${base}${path}`, { ...init, headers: { ...(init.headers || {}), Authorization: `Bearer ${auth}` } }, timeoutMs);
    if (response.status === 404 || response.status === 421) { last = response; continue; }
    if (response.status === 401) token = null;
    workingBase = base;
    return response;
  }
  return last;
}

function failure(status, body) {
  const message = body?.message || body?.error?.message || body?.raw || '';
  if (status === 401) return new ApiError(502, 'GigaChat: доступ отклонён. Проверьте ключ на сервере.');
  if (status === 402) return new ApiError(502, 'GigaChat: закончился пакет токенов. Пополните баланс в личном кабинете Сбера.');
  if (status === 429) return new ApiError(429, 'GigaChat: слишком много запросов. Подождите минуту.', { retryable: true });
  if (status >= 500) return new ApiError(502, `GigaChat временно недоступен (${status}).`, { retryable: true });
  return new ApiError(502, `GigaChat: ${message || `ошибка ${status}`}`);
}

async function uploadImage(base64) {
  const form = new FormData();
  form.append('file', new Blob([Buffer.from(base64, 'base64')], { type: 'image/jpeg' }), 'photo.jpg');
  form.append('purpose', 'general');
  const response = await call('/files', { method: 'POST', body: form }, 60_000);
  const body = await readJSON(response);
  if (!response.ok || !body.id) throw failure(response.status, body);
  return body.id;
}

/** App messages → GigaChat messages (one image per message, uploaded as a file). */
async function toMessages(system, messages) {
  const result = [];
  if (system) result.push({ role: 'system', content: system });
  for (const message of messages) {
    const item = { role: message.role === 'assistant' ? 'assistant' : 'user', content: message.text || '(без текста)' };
    if (message.image) item.attachments = [await uploadImage(message.image)];
    result.push(item);
  }
  return result;
}

const hasImages = (messages) => messages.some((m) => m.image);

export async function chat({ system, messages, maxTokens = 2000, onDelta }) {
  const body = {
    model: config.gigachat.model,
    messages: await toMessages(system, messages),
    max_tokens: Math.min(maxTokens, 32_000),
    temperature: 0.4,
    stream: Boolean(onDelta),
  };
  const response = await call('/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: onDelta ? 'text/event-stream' : 'application/json' },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw failure(response.status, await readJSON(response));
  if (!onDelta) {
    const json = await readJSON(response);
    return json?.choices?.[0]?.message?.content ?? '';
  }
  let full = '';
  await readSSE(response, (payload) => {
    if (payload === '[DONE]') return false;
    try {
      const delta = JSON.parse(payload)?.choices?.[0]?.delta?.content;
      if (delta) { full += delta; onDelta(delta); }
    } catch { /* keep-alive or partial line */ }
    return true;
  });
  return full;
}

/** Structured answer: the schema is offered as a function the model must call. */
export async function json({ system, messages, schema, name = 'result', description = 'Результат', maxTokens = 8000 }) {
  const body = {
    model: config.gigachat.model,
    messages: await toMessages(`${system}\n\nОтветь ТОЛЬКО вызовом функции ${name}.`, messages),
    functions: [{ name, description, parameters: schema }],
    function_call: { name },
    max_tokens: Math.min(maxTokens, 32_000),
    temperature: 0.3,
  };
  const response = await call('/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body),
  });
  const result = await readJSON(response);
  if (!response.ok) throw failure(response.status, result);
  const message = result?.choices?.[0]?.message ?? {};
  const args = message.function_call?.arguments;
  if (args) return parseLooseJSON(args);
  return parseLooseJSON(message.content ?? '');
}

/** Kandinsky picture through GigaChat (text → image). Returns base64 JPEG. */
export async function generateImage({ prompt }) {
  const body = {
    model: config.gigachat.model,
    messages: [
      { role: 'system', content: 'Ты — профессиональный визуализатор интерьеров. Рисуешь фотореалистично.' },
      { role: 'user', content: `Нарисуй: ${prompt}` },
    ],
    function_call: 'auto',
  };
  const response = await call('/chat/completions', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  const result = await readJSON(response);
  if (!response.ok) throw failure(response.status, result);
  const content = result?.choices?.[0]?.message?.content ?? '';
  const id = content.match(/<img[^>]+src="([^"]+)"/)?.[1];
  if (!id) throw new ApiError(502, 'GigaChat не нарисовал картинку. Попробуйте изменить описание.');
  const file = await call(`/files/${id}/content`, { method: 'GET', headers: { Accept: 'application/jpg' } }, 60_000);
  if (!file.ok) throw failure(file.status, await readJSON(file));
  return Buffer.from(await file.arrayBuffer()).toString('base64');
}

export const supportsVision = () => true;
export { hasImages };
