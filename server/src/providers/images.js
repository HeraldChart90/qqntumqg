// Photoreal edit of the exact 3D render: FLUX Kontext (bfl.ai) and/or OpenAI GPT Image — only if keys are set on the server.
import { config } from '../config.js';
import { ApiError, request, readJSON, sleep } from '../util.js';

export const editEngines = () => [config.bfl.apiKey ? 'flux' : null, config.openai.apiKey ? 'gpt' : null].filter(Boolean);

export async function fluxEdit({ image, prompt }) {
  if (!config.bfl.apiKey) throw new ApiError(400, 'FLUX не подключён на сервере.');
  const start = await request(`https://api.bfl.ai/v1/${config.bfl.model}`, {
    method: 'POST',
    headers: { 'x-key': config.bfl.apiKey, 'Content-Type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ prompt: String(prompt).slice(0, 2500), input_image: image, output_format: 'jpeg', safety_tolerance: 2, prompt_upsampling: false }),
  }, 60_000);
  const created = await readJSON(start);
  if (!start.ok || !created.polling_url) {
    if (start.status === 402) throw new ApiError(502, 'FLUX: закончились кредиты на bfl.ai.');
    if (start.status === 429) throw new ApiError(429, 'FLUX занят. Попробуйте через минуту.', { retryable: true });
    throw new ApiError(502, `FLUX: ${created.detail || `ошибка ${start.status}`}`);
  }
  const deadline = Date.now() + 180_000;
  while (Date.now() < deadline) {
    await sleep(1500);
    const poll = await request(created.polling_url, { headers: { 'x-key': config.bfl.apiKey, accept: 'application/json' } }, 30_000);
    const state = await readJSON(poll);
    if (!poll.ok) throw new ApiError(502, `FLUX: ошибка ${poll.status}`);
    if (state.status === 'Ready') {
      const sample = state.result?.sample;
      if (!sample) throw new ApiError(502, 'FLUX не вернул картинку.');
      const file = await request(sample, {}, 60_000);
      return Buffer.from(await file.arrayBuffer()).toString('base64');
    }
    if (['Request Moderated', 'Content Moderated'].includes(state.status)) throw new ApiError(422, 'FLUX отклонил запрос модерацией.');
    if (['Error', 'Failed', 'Task not found'].includes(state.status)) throw new ApiError(502, `FLUX не смог создать изображение (${state.status}).`);
  }
  throw new ApiError(504, 'FLUX не успел за 3 минуты.', { retryable: true });
}

export async function gptEdit({ image, prompt, size = '1536x1152' }) {
  if (!config.openai.apiKey) throw new ApiError(400, 'GPT Image не подключён на сервере.');
  const form = new FormData();
  form.append('model', config.openai.imageModel);
  form.append('prompt', String(prompt).slice(0, 30_000));
  form.append('size', size);
  form.append('quality', 'high');
  form.append('output_format', 'jpeg');
  form.append('n', '1');
  form.append('image[]', new Blob([Buffer.from(image, 'base64')], { type: 'image/jpeg' }), 'render.jpg');
  const response = await request('https://api.openai.com/v1/images/edits', {
    method: 'POST', headers: { Authorization: `Bearer ${config.openai.apiKey}` }, body: form,
  }, 240_000);
  const result = await readJSON(response);
  if (!response.ok) {
    const message = result?.error?.message || `ошибка ${response.status}`;
    if (response.status === 429) throw new ApiError(429, 'OpenAI: лимит или баланс исчерпан.', { retryable: true });
    throw new ApiError(502, `OpenAI: ${message}`);
  }
  const b64 = result?.data?.[0]?.b64_json;
  if (!b64) throw new ApiError(502, 'GPT не вернул изображение.');
  return b64;
}
