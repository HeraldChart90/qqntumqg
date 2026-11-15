// Yandex AI Studio: YandexGPT through the OpenAI‑compatible API, Qwen for photos, YandexART for pictures.
// Docs: https://aistudio.yandex.ru/docs/ru/ai-studio/
import { config } from '../config.js';
import { ApiError, request, readJSON, readSSE, parseLooseJSON, sleep } from '../util.js';

let workingBase = null;
const modelURI = (name) => (name.includes('://') ? name : `gpt://${config.yandex.folderId}/${name}`);
const headers = (extra = {}) => ({
  Authorization: `Api-Key ${config.yandex.apiKey}`,
  'OpenAI-Project': config.yandex.folderId,
  'x-folder-id': config.yandex.folderId,
  'Content-Type': 'application/json',
  ...extra,
});

async function call(path, body, accept = 'application/json') {
  const bases = workingBase ? [workingBase, ...config.yandex.bases.filter((b) => b !== workingBase)] : config.yandex.bases;
  let last;
  for (const base of bases) {
    const response = await request(`${base}${path}`, { method: 'POST', headers: headers({ Accept: accept }), body: JSON.stringify(body) });
    if (response.status === 404) { last = response; continue; }
    workingBase = base;
    return response;
  }
  return last;
}

function failure(status, body) {
  const message = body?.error?.message || body?.message || body?.raw || '';
  if (status === 401 || status === 403) return new ApiError(502, 'YandexGPT: доступ отклонён. Проверьте API‑ключ, folder id и роль ai.languageModels.user.');
  if (status === 429) return new ApiError(429, 'YandexGPT: слишком много запросов. Подождите минуту.', { retryable: true });
  if (status >= 500) return new ApiError(502, `YandexGPT временно недоступен (${status}).`, { retryable: true });
  return new ApiError(502, `YandexGPT: ${message || `ошибка ${status}`}`);
}

function toMessages(system, messages) {
  const result = system ? [{ role: 'system', content: system }] : [];
  for (const message of messages) {
    const role = message.role === 'assistant' ? 'assistant' : 'user';
    if (message.image) {
      result.push({ role, content: [
        { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${message.image}` } },
        { type: 'text', text: message.text || '(без текста)' },
      ] });
    } else {
      result.push({ role, content: message.text || '(без текста)' });
    }
  }
  return result;
}

const pickModel = (messages) => modelURI(messages.some((m) => m.image) ? config.yandex.visionModel : config.yandex.model);

export async function chat({ system, messages, maxTokens = 2000, onDelta }) {
  const body = { model: pickModel(messages), messages: toMessages(system, messages), max_tokens: Math.min(maxTokens, 8000), temperature: 0.4, stream: Boolean(onDelta) };
  const response = await call('/chat/completions', body, onDelta ? 'text/event-stream' : 'application/json');
  if (!response.ok) throw failure(response.status, await readJSON(response));
  if (!onDelta) return (await readJSON(response))?.choices?.[0]?.message?.content ?? '';
  let full = '';
  await readSSE(response, (payload) => {
    if (payload === '[DONE]') return false;
    try {
      const delta = JSON.parse(payload)?.choices?.[0]?.delta?.content;
      if (delta) { full += delta; onDelta(delta); }
    } catch { /* ignore */ }
    return true;
  });
  return full;
}

export async function json({ system, messages, schema, name = 'result', maxTokens = 8000 }) {
  const base = { model: pickModel(messages), messages: toMessages(`${system}\n\nОтветь ТОЛЬКО одним JSON‑объектом по схеме, без текста вокруг.`, messages), max_tokens: Math.min(maxTokens, 8000), temperature: 0.3 };
  let response = await call('/chat/completions', { ...base, response_format: { type: 'json_schema', json_schema: { name, schema } } });
  if (response.status === 400) response = await call('/chat/completions', { ...base, response_format: { type: 'json_object' } });
  const result = await readJSON(response);
  if (!response.ok) throw failure(response.status, result);
  return parseLooseJSON(result?.choices?.[0]?.message?.content ?? '');
}

/** YandexART: asynchronous generation, polled until ready. Returns base64 JPEG. */
export async function generateImage({ prompt, width = 4, height = 3 }) {
  const art = config.yandex.artModel.includes('://') ? config.yandex.artModel : `art://${config.yandex.folderId}/${config.yandex.artModel}`;
  const start = await request(`${config.yandex.nativeBase}/foundationModels/v1/imageGenerationAsync`, {
    method: 'POST', headers: headers(),
    body: JSON.stringify({
      modelUri: art,
      generationOptions: { mimeType: 'image/jpeg', aspectRatio: { widthRatio: String(width), heightRatio: String(height) } },
      messages: [{ text: String(prompt).slice(0, 500), weight: '1' }],
    }),
  }, 30_000);
  const operation = await readJSON(start);
  if (!start.ok || !operation.id) throw failure(start.status, operation);
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    await sleep(2500);
    const poll = await request(`${config.yandex.nativeBase}/operations/${operation.id}`, { headers: headers() }, 20_000);
    const state = await readJSON(poll);
    if (!poll.ok) throw failure(poll.status, state);
    if (state.done) {
      if (state.error) throw new ApiError(502, `YandexART: ${state.error.message || 'не удалось создать изображение'}`);
      const image = state.response?.image;
      if (!image) throw new ApiError(502, 'YandexART не вернул изображение.');
      return image;
    }
  }
  throw new ApiError(504, 'YandexART не успел за 2 минуты. Попробуйте ещё раз.', { retryable: true });
}

export const supportsVision = () => Boolean(config.yandex.visionModel);
