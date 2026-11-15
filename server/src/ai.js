// Chooses the provider: the first in AI_PROVIDERS that is configured; on a temporary failure — the next one.
import { config, hasGigaChat, hasYandex } from './config.js';
import { ApiError } from './util.js';
import * as gigachat from './providers/gigachat.js';
import * as yandex from './providers/yandex.js';

const registry = { gigachat: { api: gigachat, ready: hasGigaChat }, yandex: { api: yandex, ready: hasYandex } };

export function activeProviders() {
  return config.providers.filter((name) => registry[name]?.ready());
}

async function withFallback(task, { needsVision = false } = {}) {
  const names = activeProviders().filter((name) => !needsVision || registry[name].api.supportsVision());
  if (names.length === 0) throw new ApiError(503, 'ИИ на сервере не настроен. Добавьте ключ GigaChat или YandexGPT в .env.');
  let lastError;
  for (const name of names) {
    try {
      return await task(registry[name].api, name);
    } catch (error) {
      lastError = error;
      console.warn(`[ai] ${name} failed: ${error.message}`);
      // Streaming that already sent text cannot switch providers mid‑answer.
      if (error.streamStarted) break;
    }
  }
  throw lastError;
}

export const chat = (params) => withFallback((api) => api.chat(params), { needsVision: params.messages.some((m) => m.image) });
export const json = (params) => withFallback((api) => api.json(params), { needsVision: params.messages.some((m) => m.image) });
export const generateImage = (params) => withFallback((api) => api.generateImage(params));
