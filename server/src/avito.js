// Avito integration: a work order becomes a vacancy on Avito Работа (temporary / project work),
// applications and Avito Messenger chats with applicants are shown and answered inside the app.
// Tokens and the client secret live only on this server. Docs: https://developers.avito.ru/api-catalog
import fs from 'node:fs';
import path from 'node:path';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { config } from './config.js';
import { ApiError, request, readJSON } from './util.js';

const env = process.env;
const API = (env.AVITO_API || 'https://api.avito.ru').replace(/\/$/, '');
export const avitoConfig = {
  clientId: env.AVITO_CLIENT_ID || '',
  clientSecret: env.AVITO_CLIENT_SECRET || '',
  adminKey: env.AVITO_ADMIN_KEY || env.HH_ADMIN_KEY || '',
  publicURL: (env.PUBLIC_URL || '').replace(/\/$/, ''),
  /** package — only from purchased packages; packageOrSingle — also pay from the Avito wallet. */
  billing: env.AVITO_BILLING || 'package',
  autoPublish: (env.AVITO_AUTO_PUBLISH || 'true') !== 'false',
  maxPerDay: Number.parseInt(env.AVITO_MAX_PER_DAY || '5', 10),
  maxPerInstallPerDay: Number.parseInt(env.AVITO_MAX_PER_INSTALL || '2', 10),
  defaultAddress: env.AVITO_ADDRESS || 'Сочи',
  businessArea: env.AVITO_BUSINESS_AREA || '',
  profession: env.AVITO_PROFESSION || '',
  scopes: env.AVITO_SCOPES || 'user:read,job:write,job:vacancy,job:applications,job:cv,messenger:read,messenger:write',
};
export const avitoEnabled = () => Boolean(avitoConfig.clientId && avitoConfig.clientSecret);

// ---------- storage ----------
const file = path.join(config.dataDir, 'avito.json');
let db = { auth: null, orders: {}, oauthStates: {}, webhook: null, seen: [], day: '', published: 0, perInstall: {} };
try { db = { ...db, ...JSON.parse(fs.readFileSync(file, 'utf8')) }; } catch { /* first start */ }
function save() {
  fs.mkdirSync(config.dataDir, { recursive: true });
  fs.writeFileSync(`${file}.tmp`, JSON.stringify(db));
  fs.renameSync(`${file}.tmp`, file);
}
const today = () => new Date().toISOString().slice(0, 10);

// ---------- tokens ----------
async function tokenRequest(params) {
  const response = await request(`${API}/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
    body: new URLSearchParams({ client_id: avitoConfig.clientId, client_secret: avitoConfig.clientSecret, ...params }).toString(),
  }, 30_000);
  const body = await readJSON(response);
  if (!response.ok || !body.access_token) throw new ApiError(502, `Avito не выдал доступ: ${body.error_description || body.error || body.message || response.status}`);
  return { access: body.access_token, refresh: body.refresh_token || db.auth?.refresh, expiresAt: Date.now() + (Number(body.expires_in) || 86_400) * 1000 };
}

async function accessToken(force = false) {
  if (!db.auth?.access) throw new ApiError(503, 'Avito ещё не подключён. Владельцу нужно открыть ссылку подключения на сервере.');
  if (force || Date.now() >= db.auth.expiresAt - 120_000) {
    const fresh = await tokenRequest({ grant_type: 'refresh_token', refresh_token: db.auth.refresh });
    db.auth = { ...db.auth, ...fresh };
    save();
  }
  return db.auth.access;
}

function avitoError(status, body) {
  const message = body?.error?.message || body?.message || body?.error_description || (typeof body?.error === 'string' ? body.error : '') || body?.raw || '';
  if (status === 402) return new ApiError(402, 'На Avito нет пакета размещения вакансий или денег на кошельке.');
  if (status === 403) return new ApiError(403, `Avito запретил действие: ${message || 'проверьте тариф и права приложения'}.`);
  if (status === 429) return new ApiError(429, 'Avito: слишком много запросов. Попробуйте через минуту.', { retryable: true });
  if (status === 404) return new ApiError(404, 'Avito: не найдено.');
  return new ApiError(502, `Avito: ${message || `ошибка ${status}`}`);
}

async function avito(method, pathname, { query, body, retried } = {}) {
  const url = new URL(`${API}${pathname}`);
  for (const [k, v] of Object.entries(query || {})) if (v !== undefined && v !== '') url.searchParams.set(k, String(v));
  const token = await accessToken();
  const response = await request(url, {
    method,
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  }, 60_000);
  // An expired token is sometimes answered with 403 instead of 401.
  if ((response.status === 401 || response.status === 403) && !retried) {
    await accessToken(true).catch(() => {});
    return avito(method, pathname, { query, body, retried: true });
  }
  if (response.status === 204) return {};
  const json = await readJSON(response);
  if (!response.ok) throw avitoError(response.status, json);
  return json;
}

// ---------- OAuth ----------
function checkAdmin(key) {
  const a = Buffer.from(String(key || '')), b = Buffer.from(avitoConfig.adminKey);
  if (!avitoConfig.adminKey || a.length !== b.length || !timingSafeEqual(a, b)) throw new ApiError(403, 'Неверный ключ администратора.');
}

export function startURL(key) {
  checkAdmin(key);
  if (!avitoEnabled()) throw new ApiError(503, 'Добавьте AVITO_CLIENT_ID и AVITO_CLIENT_SECRET в .env.');
  const state = randomBytes(16).toString('hex');
  db.oauthStates[state] = Date.now();
  save();
  const url = new URL(env.AVITO_AUTHORIZE_URL || 'https://avito.ru/oauth');
  url.search = new URLSearchParams({ response_type: 'code', client_id: avitoConfig.clientId, scope: avitoConfig.scopes, state }).toString();
  return url.toString();
}

export async function finishOAuth(code, state) {
  const created = db.oauthStates[state];
  delete db.oauthStates[state];
  if (!created || Date.now() - created > 30 * 60_000) throw new ApiError(400, 'Ссылка подключения устарела. Откройте её заново.');
  db.auth = await tokenRequest({ grant_type: 'authorization_code', code });
  save();
  const me = await avito('GET', '/core/v1/accounts/self');
  if (!me?.id) { db.auth = null; save(); throw new ApiError(400, 'Avito не вернул профиль.'); }
  db.auth.userId = String(me.id);
  db.auth.name = me.name || '';
  save();
  await subscribeWebhooks().catch((error) => console.warn('[avito] webhooks:', error.message));
  return { name: db.auth.name, userId: db.auth.userId };
}

async function subscribeWebhooks() {
  if (!avitoConfig.publicURL) return;
  if (!db.webhook?.secret) db.webhook = { secret: randomBytes(18).toString('hex') };
  const url = `${avitoConfig.publicURL}/v1/avito/webhook/${db.webhook.secret}`;
  await avito('POST', '/messenger/v3/webhook', { body: { url } }).then(() => { db.webhook.messenger = true; }).catch((e) => console.warn('[avito] messenger webhook:', e.message));
  await avito('PUT', '/job/v1/applications/webhook', { body: { url, secret: db.webhook.secret } }).then(() => { db.webhook.applications = true; }).catch((e) => console.warn('[avito] applications webhook:', e.message));
  save();
}

// ---------- dictionaries ----------
const cache = new Map();
async function dict(id) {
  const hit = cache.get(id);
  if (hit && Date.now() - hit.at < 86_400_000) return hit.value;
  const json = await avito('GET', `/job/v2/vacancy/dict/${id}`);
  const value = (Array.isArray(json) ? json : json?.items || json?.result || []).filter((x) => !x.deprecated);
  cache.set(id, { at: Date.now(), value });
  return value;
}
const findBy = (list, words) => {
  for (const word of words) {
    const hit = list.find((x) => String(x.name).toLowerCase().includes(word));
    if (hit) return hit;
  }
  return null;
};
const PROFESSION_WORDS = {
  'Фундамент и монолит': ['бетонщик', 'монолит', 'арматурщик'],
  'Коробка и кровля': ['каменщик', 'кровельщик'],
  'Фасад и благоустройство': ['фасад', 'штукатур'],
  'Ремонт и отделка': ['отделоч', 'маляр', 'штукатур', 'плиточник'],
  'Инженерные работы': ['сантехник', 'электромонтаж', 'электрик'],
  'Металлоконструкции': ['сварщик', 'монтажник'],
};
const WORK_TYPES = {
  'Фундамент и монолит': ['concreteAndStoneWorks'], 'Коробка и кровля': ['concreteAndStoneWorks', 'roofing'],
  'Фасад и благоустройство': ['constructionOfFacades'], 'Ремонт и отделка': ['finishingWork', 'repairWork'],
  'Инженерные работы': ['mountingAndInstallation', 'installationAndConfigurationOfEquipment'], 'Металлоконструкции': ['weldingWork', 'mountingAndInstallation'],
};
async function businessArea() {
  if (avitoConfig.businessArea) return Number(avitoConfig.businessArea);
  const hit = findBy(await dict('business_area'), ['строительств', 'ремонт', 'рабоч']);
  if (!hit) throw new ApiError(502, 'Не найдена сфера «Строительство» в справочнике Avito (задайте AVITO_BUSINESS_AREA).');
  return Number(hit.id);
}
async function profession(category) {
  if (avitoConfig.profession) return Number(avitoConfig.profession);
  const list = await dict('profession').catch(() => []);
  const hit = findBy(list, [...(PROFESSION_WORDS[category] || []), 'строитель', 'разнорабоч', 'мастер']);
  return hit ? Number(hit.id) : null;
}

export async function status(key) {
  checkAdmin(key);
  if (!db.auth) return { connected: false, enabled: avitoEnabled() };
  const area = await businessArea().catch((e) => ({ error: e.message }));
  return { connected: true, name: db.auth.name, userId: db.auth.userId, webhook: db.webhook || null, billing: avitoConfig.billing, businessArea: area, publishedToday: db.day === today() ? db.published : 0 };
}

// ---------- vacancy from a work order ----------
const TITLES = {
  'Строительные работы': 'Строитель', 'Фундамент и монолит': 'Бетонщик-монолитчик', 'Коробка и кровля': 'Каменщик, кровельщик',
  'Фасад и благоустройство': 'Мастер фасадных работ', 'Ремонт и отделка': 'Мастер-отделочник', 'Инженерные работы': 'Сантехник, электромонтажник',
  'Металлоконструкции': 'Сварщик-монтажник', 'Другое': 'Мастер строительных работ',
};
const escapeHTML = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function description(order) {
  const lines = String(order.details || '').trim().split(/\n+/).filter(Boolean).slice(0, 30).map((l) => `<li>${escapeHTML(l.slice(0, 300))}</li>`).join('');
  return [
    `<p><strong>Работа на объекте в г. ${escapeHTML(order.city || avitoConfig.defaultAddress)}, по договору подряда.</strong></p>`,
    `<p><strong>Вид работ:</strong> ${escapeHTML(order.category)}</p>`,
    lines ? `<p><strong>Задача:</strong></p><ul>${lines}</ul>` : '',
    order.budget ? `<p><strong>Ориентир бюджета объекта:</strong> ${escapeHTML(order.budget)}</p>` : '',
    '<p><strong>Условия:</strong></p><ul><li>оплата по этапам и актам;</li><li>самозанятость, ИП или ГПХ;</li><li>фотоотчёты по этапам.</li></ul>',
    '<p>Откликайтесь — обсудим сроки и стоимость в чате.</p>',
  ].join('').slice(0, 5000);
}

export async function publishOrder(installId, order) {
  if (!avitoEnabled()) throw new ApiError(503, 'Интеграция с Avito не настроена на сервере.');
  if (!avitoConfig.autoPublish) throw new ApiError(409, 'Автопубликация на Avito выключена владельцем.');
  const orderId = String(order.orderId || '').slice(0, 80);
  if (!orderId) throw new ApiError(400, 'Нет номера заявки.');
  const existing = db.orders[orderId];
  if (existing?.vacancyId) {
    if (existing.installId !== installId) throw new ApiError(403, 'Заявка принадлежит другому устройству.');
    return { status: 'published', vacancyId: existing.vacancyId, url: existing.url, token: existing.token };
  }
  if (db.day !== today()) { db.day = today(); db.published = 0; db.perInstall = {}; }
  if (db.published >= avitoConfig.maxPerDay) throw new ApiError(429, 'Сегодня лимит публикаций на Avito исчерпан. Заявка уже у АртСтроя.');
  if ((db.perInstall[installId] || 0) >= avitoConfig.maxPerInstallPerDay) throw new ApiError(429, 'С этого устройства сегодня уже опубликованы заявки на Avito.');

  const title = TITLES[order.category] || TITLES['Другое'];
  const city = String(order.city || avitoConfig.defaultAddress).trim();
  const body = {
    name: `${title}, ${city.split(',')[0]}`.slice(0, 50),
    description: description(order),
    billing_type: avitoConfig.billing,
    business_area: await businessArea(),
    employment: 'temporary',
    schedule: { id: 'flexible' },
    experience: { id: 'moreThan1' },
    address: /сочи|адлер|хоста|лазаревск|дагомыс|красная поляна|сириус/i.test(city) && !/сочи/i.test(city) ? `Сочи, ${city}` : city,
    work_format: ['office'],
    registration_method: ['gph_self_employed', 'gph_ip', 'gph_individual'],
    allow_messages: true,
    vacancy_code: orderId.slice(0, 150),
  };
  const prof = await profession(order.category);
  if (prof) body.profession = prof;
  const types = WORK_TYPES[order.category];
  if (types) body.construction_work_type = types;
  const created = await avito('POST', '/job/v1/vacancies', { body });
  const vacancyId = String(created?.id || '');
  if (!vacancyId) throw new ApiError(502, 'Avito не вернул номер вакансии.');
  const token = randomBytes(24).toString('hex');
  db.orders[orderId] = { vacancyId, token, installId, url: created.url || `https://www.avito.ru/${vacancyId}`, createdAt: Date.now(), title: body.name };
  db.published += 1;
  db.perInstall[installId] = (db.perInstall[installId] || 0) + 1;
  save();
  return { status: 'published', vacancyId, url: db.orders[orderId].url, token, note: 'Вакансия отправлена на Avito и проходит модерацию.' };
}

function orderFor(orderId, token) {
  const order = db.orders[String(orderId)];
  if (!order) throw new ApiError(404, 'Эта заявка не публиковалась на Avito.');
  const a = Buffer.from(String(token || '')), b = Buffer.from(order.token);
  if (a.length !== b.length || !timingSafeEqual(a, b)) throw new ApiError(403, 'Нет доступа к откликам этой заявки.');
  return order;
}

// ---------- applications & chats ----------
function experienceText(value) {
  if (!value) return '';
  if (value === '0' || value === 'no_experience') return 'без опыта';
  if (value === 'lt_1') return 'меньше года';
  const years = Number(value);
  return Number.isFinite(years) ? `${years} г.` : '';
}

/** Only what the client needs: name and experience, no phones, age or birthday. */
function publicApplicant(item) {
  const full = item.applicant?.data?.full_name || {};
  const name = [full.first_name, full.last_name ? `${String(full.last_name)[0]}.` : ''].filter(Boolean).join(' ')
    || String(item.applicant?.data?.name || '').split(' ').slice(0, 1).join(' ') || 'Соискатель';
  return {
    id: String(item.id),
    chatId: item.contacts?.chat?.value ? String(item.contacts.chat.value) : null,
    name,
    title: '',
    area: '',
    experience: experienceText(item.enriched_properties?.experience?.value),
    skills: [],
    state: item.is_viewed ? 'Просмотрен' : 'Новый отклик',
    createdAt: item.created_at || '',
    unread: item.is_viewed ? 0 : 1,
  };
}

export async function responses(orderId, token) {
  const order = orderFor(orderId, token);
  const ids = await avito('GET', '/job/v1/applications/get_ids', { query: { vacancyIds: order.vacancyId, createdAtFrom: new Date(order.createdAt - 86_400_000).toISOString().slice(0, 10) } });
  const list = (ids?.applies || []).map((a) => a.id).slice(0, 100);
  const applies = list.length ? (await avito('POST', '/job/v1/applications/get_by_ids', { body: { ids: list } }))?.applies || [] : [];
  return {
    vacancy: { id: order.vacancyId, url: order.url, title: order.title, status: 'Опубликована на Avito' },
    applicants: applies.filter((a) => String(a.vacancy_id || order.vacancyId) === String(order.vacancyId)).map(publicApplicant)
      .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))),
  };
}

const CHAT_ID = /^[A-Za-z0-9~_-]{3,120}$/;
async function checkChat(order, chatId) {
  if (!CHAT_ID.test(String(chatId))) throw new ApiError(400, 'Неверный чат.');
  const chat = await avito('GET', `/messenger/v2/accounts/${db.auth.userId}/chats/${encodeURIComponent(chatId)}`);
  const itemId = chat?.context?.value?.id;
  if (itemId && String(itemId) !== String(order.vacancyId)) throw new ApiError(403, 'Чат относится к другой вакансии.');
  return chat;
}

export async function messages(orderId, token, chatId) {
  const order = orderFor(orderId, token);
  const chat = await checkChat(order, chatId);
  const json = await avito('GET', `/messenger/v3/accounts/${db.auth.userId}/chats/${encodeURIComponent(chatId)}/messages/`, { query: { limit: 100 } });
  const list = Array.isArray(json) ? json : json?.messages || [];
  avito('POST', `/messenger/v1/accounts/${db.auth.userId}/chats/${encodeURIComponent(chatId)}/read`).catch(() => {});
  const other = (chat?.users || []).find((u) => String(u.id) !== String(db.auth.userId));
  return {
    canWrite: true,
    messages: list.filter((m) => m.content?.text).map((m) => ({
      id: String(m.id),
      text: m.content.text,
      fromClient: m.direction === 'out',
      name: m.direction === 'out' ? 'Вы' : (other?.name || 'Соискатель'),
      createdAt: m.created ? new Date(Number(m.created) * 1000).toISOString() : '',
    })).sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt))),
  };
}

export async function sendMessage(orderId, token, chatId, text) {
  const order = orderFor(orderId, token);
  const clean = String(text || '').trim().slice(0, 1000);
  if (!clean) throw new ApiError(400, 'Пустое сообщение.');
  await checkChat(order, chatId);
  await avito('POST', `/messenger/v1/accounts/${db.auth.userId}/chats/${encodeURIComponent(chatId)}/messages`, { body: { message: { text: clean }, type: 'text' } });
  return { ok: true };
}

export function webhook(secret, event) {
  if (!db.webhook?.secret || secret !== db.webhook.secret) throw new ApiError(404, 'Не найдено');
  const id = event?.id || event?.payload?.value?.id;
  if (!id) return { duplicate: false };
  if (db.seen.includes(id)) return { duplicate: true };
  db.seen = [...db.seen.slice(-500), id];
  save();
  return { duplicate: false };
}

// ---------- market search (other employers' vacancies on Avito Работа) ----------
export async function searchVacancies({ text, city }) {
  if (!db.auth?.access) return [];
  const query = { per_page: 100, page: 1, business_area: await businessArea().catch(() => '') };
  if (env.AVITO_LOCATION_ID) query.location = env.AVITO_LOCATION_ID;
  const json = await avito('GET', '/job/v2/vacancies', { query });
  const want = String(city || 'Сочи').split(',')[0].trim().toLowerCase();
  const words = String(text || '').toLowerCase().split(/\s+/).filter((w) => w.length > 2 && !['or', 'and'].includes(w));
  return (json?.vacancies || [])
    .filter((v) => !want || `${v.addressDetails?.city || ''} ${v.addressDetails?.address || ''}`.toLowerCase().includes(want))
    .filter((v) => words.length === 0 || words.some((w) => `${v.title} ${v.profession || ''}`.toLowerCase().includes(w)))
    .slice(0, 40)
    .map((v) => ({
      board: 'avito', id: String(v.link || v.title), title: v.title || '', company: v.companyName || '', city: v.addressDetails?.city || '',
      salary: '', url: v.link || 'https://www.avito.ru/', publishedAt: '', snippet: v.profession || v.businessArea || '',
    }));
}

// ---------- resume search on Avito Работа (owner only) ----------
const photoCache = new Map();
async function resumePhoto(id) {
  const hit = photoCache.get(id);
  if (hit && Date.now() - hit.at < 3_600_000) return hit.url;
  const json = await avito('GET', `/job/v2/resumes/${id}`, { query: { photos: true, fields: 'title' } }).catch(() => null);
  const url = json?.photos?.[0]?.url || '';
  photoCache.set(id, { at: Date.now(), url });
  return url;
}

export async function searchResumes({ text, city, page = 0 }) {
  if (!db.auth?.access) return [];
  const want = String(city || 'Сочи').split(',')[0].trim().toLowerCase();
  const query = { query: text || 'строитель', per_page: 100, page: page + 1, fields: 'title,location,specialization,total_experience,age,salary,address_details,updated_at' };
  if (env.AVITO_LOCATION_ID) query.location = env.AVITO_LOCATION_ID;
  const json = await avito('GET', '/job/v1/resumes/', { query });
  const list = (json?.resumes || []).filter((r) => !want || `${r.location?.title || ''} ${r.address_details?.location || ''} ${r.address_details?.address || ''}`.toLowerCase().includes(want)).slice(0, 20);
  const photos = await Promise.all(list.slice(0, 12).map((r) => resumePhoto(r.id)));
  return list.map((r, i) => ({
    board: 'avito', id: String(r.id), name: r.title ? '' : 'Соискатель', title: r.title || r.specialization?.title || '',
    city: r.location?.title || r.address_details?.location || '', age: r.age || null,
    experience: r.total_experience ? `${r.total_experience} г.` : '',
    salary: r.salary ? `${Number(r.salary).toLocaleString('ru-RU')} ₽` : '',
    photo: photos[i] || '', lastJob: r.specialization?.title || '',
    url: `https://www.avito.ru/${r.id}`, updatedAt: r.updated_at || r.updated || '',
  }));
}
