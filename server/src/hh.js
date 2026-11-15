// hh.ru integration: a work order from the app becomes a vacancy on hh.ru (employment PROJECT),
// responses and chats with applicants are shown and answered inside the app.
// All hh tokens and the client secret live only on this server. Docs: https://api.hh.ru/openapi/redoc
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID, randomBytes, timingSafeEqual } from 'node:crypto';
import { config } from './config.js';
import { ApiError, request, readJSON } from './util.js';

const API = (process.env.HH_API || 'https://api.hh.ru').replace(/\/$/, '');
const env = process.env;
export const hhConfig = {
  clientId: env.HH_CLIENT_ID || '',
  clientSecret: env.HH_CLIENT_SECRET || '',
  redirectURI: env.HH_REDIRECT_URI || '',
  userAgent: env.HH_USER_AGENT || 'ArtStroy/1.0 (info@sochi-art.com)',
  adminKey: env.HH_ADMIN_KEY || '',
  publicURL: (env.PUBLIC_URL || '').replace(/\/$/, ''),
  /** free — publish only with the free hh tariff; any — also spend purchased publications. */
  publication: (env.HH_PUBLICATION || 'free').toLowerCase(),
  autoPublish: (env.HH_AUTO_PUBLISH || 'true') !== 'false',
  maxPerDay: Number.parseInt(env.HH_MAX_PER_DAY || '5', 10),
  maxPerInstallPerDay: Number.parseInt(env.HH_MAX_PER_INSTALL || '2', 10),
  defaultAreaId: env.HH_AREA_ID || '',
  roleId: env.HH_ROLE_ID || '',
  contactName: env.HH_CONTACT_NAME || '',
  contactPhone: env.HH_CONTACT_PHONE || '',
};
export const hhEnabled = () => Boolean(hhConfig.clientId && hhConfig.clientSecret && hhConfig.redirectURI);

// ---------- storage ----------
const file = path.join(config.dataDir, 'hh.json');
let db = { auth: null, orders: {}, oauthStates: {}, webhook: null, seen: [], day: '', published: 0, perInstall: {}, unread: {} };
try { db = { ...db, ...JSON.parse(fs.readFileSync(file, 'utf8')) }; } catch { /* first start */ }
function save() {
  fs.mkdirSync(config.dataDir, { recursive: true });
  fs.writeFileSync(`${file}.tmp`, JSON.stringify(db));
  fs.renameSync(`${file}.tmp`, file);
}
const today = () => new Date().toISOString().slice(0, 10);

// ---------- hh requests ----------
const baseHeaders = () => ({ 'HH-User-Agent': hhConfig.userAgent, 'User-Agent': hhConfig.userAgent, Accept: 'application/json' });

async function tokenRequest(params) {
  const response = await request(`${API}/token`, {
    method: 'POST',
    headers: { ...baseHeaders(), 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params).toString(),
  }, 30_000);
  const body = await readJSON(response);
  if (!response.ok || !body.access_token) {
    throw new ApiError(502, `hh.ru не выдал доступ: ${body.error_description || body.error || response.status}`);
  }
  return { access: body.access_token, refresh: body.refresh_token, expiresAt: Date.now() + (Number(body.expires_in) || 1_209_600) * 1000 };
}

async function accessToken() {
  if (!db.auth?.access) throw new ApiError(503, 'hh.ru ещё не подключён. Владельцу нужно открыть ссылку подключения на сервере.');
  // hh allows refreshing only after the access token expired, and each refresh token works once.
  if (Date.now() >= db.auth.expiresAt - 60_000) {
    const fresh = await tokenRequest({ grant_type: 'refresh_token', refresh_token: db.auth.refresh });
    db.auth = { ...db.auth, ...fresh };
    save();
  }
  return db.auth.access;
}

const ERRORS = {
  not_enough_purchased_services: 'На аккаунте hh.ru нет оплаченных публикаций нужного типа.',
  quota_exceeded: 'Исчерпана квота публикаций менеджера на hh.ru.',
  duplicate: 'Такая вакансия уже опубликована на hh.ru.',
  creation_forbidden: 'hh.ru запретил создавать вакансии с этого аккаунта.',
  bad_json_data: 'hh.ru не принял данные вакансии.',
  captcha_required: 'hh.ru просит пройти капчу: зайдите в кабинет работодателя на сайте.',
  token_expired: 'Доступ к hh.ru устарел, переподключите аккаунт.',
  bad_authorization: 'Доступ к hh.ru отозван, переподключите аккаунт.',
};
function hhError(status, body) {
  const first = body?.errors?.[0] || {};
  const known = ERRORS[first.value] || ERRORS[first.type];
  const detail = body?.description || first.value || first.type || body?.raw || status;
  return new ApiError(status === 404 || status === 403 ? status : 502, known ? `${known}` : `hh.ru: ${detail}`);
}

async function hh(method, pathname, { query, body, retried } = {}) {
  const url = new URL(pathname.startsWith('http') ? pathname : `${API}${pathname}`);
  for (const [k, v] of Object.entries(query || {})) if (v !== undefined && v !== '') url.searchParams.set(k, String(v));
  const token = await accessToken();
  const response = await request(url, {
    method,
    headers: { ...baseHeaders(), Authorization: `Bearer ${token}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  }, 60_000);
  if (response.status === 204) return { status: 204, headers: response.headers, json: {} };
  const json = await readJSON(response);
  if ((response.status === 401 || response.status === 403) && !retried && json?.errors?.some((e) => e.value === 'token_expired')) {
    db.auth.expiresAt = 0; // force refresh once
    return hh(method, pathname, { query, body, retried: true });
  }
  if (!response.ok) throw hhError(response.status, json);
  return { status: response.status, headers: response.headers, json };
}

// ---------- OAuth (owner connects the АртСтрой employer account once) ----------
function checkAdmin(key) {
  const a = Buffer.from(String(key || '')), b = Buffer.from(hhConfig.adminKey);
  if (!hhConfig.adminKey || a.length !== b.length || !timingSafeEqual(a, b)) throw new ApiError(403, 'Неверный ключ администратора.');
}

export function startURL(key) {
  checkAdmin(key);
  const state = randomBytes(16).toString('hex');
  db.oauthStates[state] = Date.now();
  save();
  const url = new URL(process.env.HH_AUTHORIZE_URL || 'https://hh.ru/oauth/authorize');
  url.search = new URLSearchParams({ response_type: 'code', client_id: hhConfig.clientId, redirect_uri: hhConfig.redirectURI, state, role: 'employer', force_role: 'true' }).toString();
  return url.toString();
}

export async function finishOAuth(code, state) {
  const created = db.oauthStates[state];
  delete db.oauthStates[state];
  if (!created || Date.now() - created > 30 * 60_000) throw new ApiError(400, 'Ссылка подключения устарела. Откройте её заново.');
  const tokens = await tokenRequest({ grant_type: 'authorization_code', client_id: hhConfig.clientId, client_secret: hhConfig.clientSecret, code, redirect_uri: hhConfig.redirectURI });
  db.auth = { ...tokens };
  save();
  const me = (await hh('GET', '/me')).json;
  if (!me?.employer?.id) { db.auth = null; save(); throw new ApiError(400, 'Войдите на hh.ru как работодатель (не соискатель) и повторите.'); }
  db.auth.employerId = String(me.employer.id);
  db.auth.managerId = String(me.manager?.id || me.employer?.manager_id || '');
  db.auth.employerName = me.employer.name || '';
  save();
  await subscribeWebhook().catch((error) => console.warn('[hh] webhook:', error.message));
  return { employer: db.auth.employerName, employerId: db.auth.employerId };
}

async function subscribeWebhook() {
  if (!hhConfig.publicURL) return;
  if (!db.webhook?.secret) db.webhook = { secret: randomBytes(18).toString('hex') };
  const url = `${hhConfig.publicURL}/v1/hh/webhook/${db.webhook.secret}`;
  const actions = ['NEW_RESPONSE_OR_INVITATION_VACANCY', 'CHAT_MESSAGE_CREATED', 'VACANCY_PUBLICATION_FOR_VACANCY_MANAGER'].map((type) => ({ type }));
  const existing = (await hh('GET', '/webhook/subscriptions')).json?.items || [];
  for (const item of existing) await hh('DELETE', `/webhook/subscriptions/${item.id}`).catch(() => {});
  const created = await hh('POST', '/webhook/subscriptions', { body: { url, actions } });
  db.webhook.id = created.json?.id || null;
  save();
}

export async function status(key) {
  checkAdmin(key);
  if (!db.auth) return { connected: false };
  const area = await resolveArea('Сочи').catch(() => null);
  const role = await resolveRole('Строительные работы').catch(() => null);
  const publications = area && role ? await publicationVariants(area, role).catch((e) => ({ error: e.message })) : null;
  return { connected: true, employer: db.auth.employerName, employerId: db.auth.employerId, webhook: Boolean(db.webhook?.id), publishedToday: db.day === today() ? db.published : 0, publication: hhConfig.publication, checkedFor: { areaId: area, roleId: role, role: roleNames.get(String(role)) || '' }, publications };
}

// ---------- dictionaries ----------
const cache = new Map();
async function cached(key, ttlMs, load) {
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < ttlMs) return hit.value;
  const value = await load();
  cache.set(key, { at: Date.now(), value });
  return value;
}

async function resolveArea(city) {
  const clean = String(city || '').split(/[,(]/)[0].trim() || 'Сочи';
  return cached(`area:${clean.toLowerCase()}`, 7 * 86_400_000, async () => {
    const found = (await hh('GET', '/suggests/areas', { query: { text: clean } }).catch(() => null))?.json?.items?.[0]?.id;
    if (found) return String(found);
    if (hhConfig.defaultAreaId) return hhConfig.defaultAreaId;
    const sochi = (await hh('GET', '/suggests/areas', { query: { text: 'Сочи' } })).json?.items?.[0]?.id;
    if (!sochi) throw new ApiError(502, 'Не удалось определить город на hh.ru.');
    return String(sochi);
  });
}

const roleNames = new Map();
const ROLE_WORDS = {
  'Фундамент и монолит': ['бетонщик', 'монолит', 'арматурщик', 'строитель'],
  'Коробка и кровля': ['каменщик', 'кровельщик', 'строитель'],
  'Фасад и благоустройство': ['фасад', 'штукатур', 'строитель'],
  'Ремонт и отделка': ['отделоч', 'маляр', 'штукатур', 'плиточник', 'строитель'],
  'Инженерные работы': ['сантехник', 'электромонтаж', 'электрик', 'монтажник'],
  'Металлоконструкции': ['сварщик', 'монтажник', 'слесарь'],
};
async function resolveRole(category) {
  if (hhConfig.roleId) return hhConfig.roleId;
  return cached(`role:${category}`, 7 * 86_400_000, async () => {
    const categories = (await hh('GET', '/professional_roles')).json?.categories || [];
    // Purchased packages are tied to a tariff group («Рабочие»): look in «Рабочий персонал» first,
    // otherwise "строитель" would match «Инженер‑строитель» from another (unpaid) group.
    const workers = categories.filter((c) => /рабоч/i.test(String(c.name))).flatMap((c) => c.roles || []);
    const all = categories.flatMap((c) => c.roles || []);
    const words = [...(ROLE_WORDS[category] || []), 'строитель', 'разнорабоч'];
    for (const pool of [workers, all]) {
      for (const word of words) {
        const role = pool.find((r) => String(r.name).toLowerCase().includes(word));
        if (role) { roleNames.set(String(role.id), role.name); return String(role.id); }
      }
    }
    throw new ApiError(502, 'Не найдена подходящая профессия в справочнике hh.ru (задайте HH_ROLE_ID).');
  });
}

async function publicationVariants(areaId, roleId) {
  const json = (await hh('GET', `/employers/${db.auth.employerId}/services/available_publications`, { query: { area_id: areaId, professional_role_id: roleId } })).json;
  return (json?.publication_variants || []).map((v) => {
    const props = v.vacancy_properties?.required || [];
    const pkg = (v.suitable_packages || []).find((p) => !p.invalid && Number(p.count) > 0);
    return {
      title: v.appearance?.title || props.map((p) => p.property_type).join(', '),
      free: props.some((p) => p.property_type === 'HH_FREE'),
      count: Number(v.available_publications_count) || 0,
      properties: props.map((p) => (p.parameters?.length ? { property_type: p.property_type, parameters: p.parameters } : { property_type: p.property_type })),
      serviceId: pkg?.employer_service_id || null,
      packages: (v.suitable_packages || []).map((p) => ({ count: p.count, invalid: p.invalid, regions: (p.price_regions || []).map((r) => r.title), groups: (p.prof_role_group || []).map((g) => g.title) })),
      usable: Number(v.available_publications_count) > 0 || Boolean(pkg),
    };
  });
}

// ---------- vacancy from a work order ----------
const TITLES = {
  'Строительные работы': 'Строитель', 'Фундамент и монолит': 'Бетонщик‑монолитчик', 'Коробка и кровля': 'Каменщик / кровельщик',
  'Фасад и благоустройство': 'Мастер фасадных работ', 'Ремонт и отделка': 'Мастер‑отделочник', 'Инженерные работы': 'Сантехник / электромонтажник',
  'Металлоконструкции': 'Сварщик‑монтажник металлоконструкций', 'Другое': 'Мастер строительных работ',
};
const escapeHTML = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function vacancyDescription(order) {
  const lines = String(order.details || '').trim().split(/\n+/).filter(Boolean).slice(0, 40).map((l) => `<li>${escapeHTML(l.slice(0, 400))}</li>`).join('');
  return [
    `<p><strong>Проектная работа на объекте в г. ${escapeHTML(order.city || 'Сочи')}.</strong> Ищем исполнителя на задачу:</p>`,
    `<p><strong>Вид работ:</strong> ${escapeHTML(order.category)}</p>`,
    lines ? `<p><strong>Задача:</strong></p><ul>${lines}</ul>` : '',
    order.budget ? `<p><strong>Ориентир бюджета объекта:</strong> ${escapeHTML(order.budget)}</p>` : '',
    '<p><strong>Условия:</strong></p><ul><li>оплата по договору подряда / самозанятость, по этапам и актам;</li><li>материалы и объёмы — по смете;</li><li>фотоотчёты по этапам.</li></ul>',
    '<p>Откликайтесь — обсудим сроки и стоимость в чате.</p>',
  ].join('');
}

/** Called by the app right after a work order was created. */
export async function publishOrder(installId, order) {
  if (!hhEnabled()) throw new ApiError(503, 'Интеграция с hh.ru не настроена на сервере.');
  if (!hhConfig.autoPublish) throw new ApiError(409, 'Автопубликация на hh.ru выключена владельцем.');
  const orderId = String(order.orderId || '').slice(0, 80);
  if (!orderId) throw new ApiError(400, 'Нет номера заявки.');
  const existing = db.orders[orderId];
  if (existing?.vacancyId) {
    if (existing.installId !== installId) throw new ApiError(403, 'Заявка принадлежит другому устройству.');
    return { status: 'published', vacancyId: existing.vacancyId, url: existing.url, token: existing.token };
  }
  if (db.day !== today()) { db.day = today(); db.published = 0; db.perInstall = {}; }
  if (db.published >= hhConfig.maxPerDay) throw new ApiError(429, 'Сегодня лимит публикаций на hh.ru исчерпан. Заявка уже у АртСтроя.');
  if ((db.perInstall[installId] || 0) >= hhConfig.maxPerInstallPerDay) throw new ApiError(429, 'С этого устройства сегодня уже опубликованы заявки на hh.ru.');

  const areaId = await resolveArea(order.city);
  const roleId = await resolveRole(order.category);
  const variants = await publicationVariants(areaId, roleId);
  const variant = variants.find((v) => v.free && v.usable) || (hhConfig.publication === 'any' ? variants.find((v) => v.usable) : null);
  if (!variant) {
    throw new ApiError(402, hhConfig.publication === 'any'
      ? 'На аккаунте hh.ru нет доступных публикаций для этого города и профессии.'
      : 'Бесплатная публикация на hh.ru сейчас недоступна. Владелец может разрешить платные (HH_PUBLICATION=any).');
  }
  const title = TITLES[order.category] || TITLES['Другое'];
  const body = {
    name: `${title} (проект, ${String(order.city || 'Сочи').split(',')[0].trim()})`.slice(0, 100),
    description: vacancyDescription(order),
    area: { id: areaId },
    professional_roles: [{ id: roleId }],
    vacancy_properties: { properties: variant.properties },
    employment_form: { id: 'PROJECT' },
    work_format: [{ id: 'ON_SITE' }],
    experience: { id: 'between1And3' },
    response_letter_required: false,
  };
  if (variant.serviceId) body.employer_service_id = variant.serviceId;
  if (hhConfig.contactName && hhConfig.contactPhone) {
    body.contacts = { name: hhConfig.contactName, phones: [{ formatted: hhConfig.contactPhone }] };
  }
  const created = await hh('POST', '/vacancies', { body });
  const vacancyId = String(created.json?.id || created.headers.get('location')?.split('/').pop() || '');
  if (!vacancyId) throw new ApiError(502, 'hh.ru не вернул номер вакансии.');
  const token = randomBytes(24).toString('hex');
  db.orders[orderId] = { vacancyId, token, installId, url: `https://hh.ru/vacancy/${vacancyId}`, createdAt: Date.now(), title: body.name };
  db.published += 1;
  db.perInstall[installId] = (db.perInstall[installId] || 0) + 1;
  save();
  return { status: 'published', vacancyId, url: db.orders[orderId].url, token, note: 'Вакансия ушла на модерацию hh.ru (обычно до нескольких часов).' };
}

function orderFor(orderId, token) {
  const order = db.orders[String(orderId)];
  if (!order) throw new ApiError(404, 'Эта заявка не публиковалась на hh.ru.');
  const a = Buffer.from(String(token || '')), b = Buffer.from(order.token);
  if (a.length !== b.length || !timingSafeEqual(a, b)) throw new ApiError(403, 'Нет доступа к откликам этой заявки.');
  return order;
}

// ---------- responses & chats ----------
/** Only what the client needs to choose an executor: no contacts, photo or age (applicant data stays on hh.ru). */
function publicApplicant(item) {
  const resume = item.resume || {};
  const months = Number(resume.total_experience?.months) || 0;
  return {
    id: String(item.id),
    chatId: item.chat_id ? String(item.chat_id) : null,
    name: [resume.first_name, resume.last_name ? `${String(resume.last_name)[0]}.` : ''].filter(Boolean).join(' ') || 'Соискатель',
    title: resume.title || '',
    area: resume.area?.name || '',
    experience: months ? `${Math.floor(months / 12)} г. ${months % 12} мес.` : '',
    skills: (resume.skill_set || []).slice(0, 6),
    state: item.employer_state?.name || item.state?.name || '',
    createdAt: item.created_at || '',
    unread: Number(item.counters?.unread_messages) || 0,
  };
}

export async function responses(orderId, token) {
  const order = orderFor(orderId, token);
  const overview = (await hh('GET', '/negotiations', { query: { vacancy_id: order.vacancyId } })).json;
  const urls = (overview?.collections || []).map((c) => c.url).filter(Boolean).slice(0, 6);
  if (urls.length === 0) urls.push(`${API}/negotiations/response?vacancy_id=${order.vacancyId}`);
  const seen = new Map();
  for (const url of urls) {
    const list = (await hh('GET', url, { query: { per_page: 50 } }).catch(() => null))?.json?.items || [];
    for (const item of list) if (!seen.has(item.id)) seen.set(item.id, publicApplicant(item));
  }
  const vacancy = (await hh('GET', `/vacancies/${order.vacancyId}`).catch(() => null))?.json;
  return {
    vacancy: { id: order.vacancyId, url: order.url, title: order.title, status: vacancy?.approved === false ? 'На модерации hh.ru' : (vacancy?.archived ? 'В архиве' : 'Опубликована') },
    applicants: [...seen.values()].sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))),
  };
}

async function chatOfOrder(order, chatId) {
  if (!/^\d{1,20}$/.test(String(chatId))) throw new ApiError(400, 'Неверный чат.');
  const json = (await hh('GET', `/common/chats/${chatId}/messages`, { query: { limit: 100 } })).json;
  if (json?.vacancy_id && String(json.vacancy_id) !== String(order.vacancyId)) throw new ApiError(403, 'Чат относится к другой вакансии.');
  return json;
}

export async function messages(orderId, token, chatId) {
  const order = orderFor(orderId, token);
  const json = await chatOfOrder(order, chatId);
  delete db.unread[chatId];
  return {
    canWrite: json?.chat_states?.write_message_state?.allowed !== false,
    messages: (json?.messages || []).filter((m) => m.payload?.text).map((m) => ({
      id: String(m.id),
      text: m.payload.text,
      fromClient: m.sender_display_info?.role === 'EMPLOYER',
      name: m.sender_display_info?.role === 'EMPLOYER' ? 'Вы' : (m.sender_display_info?.name || 'Соискатель'),
      createdAt: m.creation_time || '',
    })).sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt))),
  };
}

export async function sendMessage(orderId, token, chatId, text) {
  const order = orderFor(orderId, token);
  const clean = String(text || '').trim().slice(0, 2000);
  if (!clean) throw new ApiError(400, 'Пустое сообщение.');
  await chatOfOrder(order, chatId);
  await hh('POST', `/common/chats/${chatId}/messages`, { body: { idempotency_key: randomUUID(), text: clean } });
  return { ok: true };
}

// ---------- webhook ----------
export function webhook(secret, event) {
  if (!db.webhook?.secret || secret !== db.webhook.secret) throw new ApiError(404, 'Не найдено');
  if (!event?.id) return { duplicate: false };
  if (db.seen.includes(event.id)) return { duplicate: true };
  db.seen = [...db.seen.slice(-500), event.id];
  const chatId = event.payload?.chat_id ? String(event.payload.chat_id) : null;
  if (chatId && event.payload?.role !== 'EMPLOYER') db.unread[chatId] = (db.unread[chatId] || 0) + 1;
  save();
  return { duplicate: false };
}

// ---------- market search (other employers' vacancies) ----------
function salaryText(v) {
  const r = v.salary_range || v.salary;
  if (!r || (!r.from && !r.to)) return '';
  const f = (n) => Number(n).toLocaleString('ru-RU');
  const cur = (r.currency || 'RUR') === 'RUR' ? '₽' : r.currency;
  if (r.from && r.to) return `${f(r.from)}–${f(r.to)} ${cur}`;
  return r.from ? `от ${f(r.from)} ${cur}` : `до ${f(r.to)} ${cur}`;
}
const stripTags = (s) => String(s || '').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();

export async function searchVacancies({ text, city, page = 0 }) {
  if (!db.auth?.access) return [];
  const area = await resolveArea(city || 'Сочи').catch(() => hhConfig.defaultAreaId || '237');
  const json = (await hh('GET', '/vacancies', { query: { text: text || 'строитель OR отделочник OR ремонт', area, per_page: 30, page, order_by: 'publication_time' } })).json;
  return (json?.items || []).map((v) => ({
    board: 'hh', id: String(v.id), title: v.name || '', company: v.employer?.name || '', city: v.area?.name || '',
    salary: salaryText(v), url: v.alternate_url || `https://hh.ru/vacancy/${v.id}`, publishedAt: v.published_at || '',
    snippet: stripTags(v.snippet?.responsibility || v.snippet?.requirement || '').slice(0, 220),
  }));
}

// ---------- resume search (owner only: hh.ru resume database access is needed) ----------
export async function searchResumes({ text, city, page = 0 }) {
  if (!db.auth?.access) return [];
  const area = await resolveArea(city || 'Сочи').catch(() => hhConfig.defaultAreaId || '237');
  let json;
  try {
    json = (await hh('GET', '/resumes', { query: { text: text || 'строитель', area, per_page: 20, page, order_by: 'relevance' } })).json;
  } catch (error) {
    if (error.status === 403) throw new ApiError(403, 'Для поиска резюме на hh.ru нужен доступ к базе резюме (платная услуга hh.ru для работодателей).');
    throw error;
  }
  return (json?.items || []).map((r) => {
    const months = Number(r.total_experience?.months) || 0;
    const last = (r.experience || [])[0];
    return {
      board: 'hh', id: String(r.id), name: [r.first_name, r.last_name].filter(Boolean).join(' ') || 'Соискатель',
      title: r.title || '', city: r.area?.name || '', age: r.age || null,
      experience: months ? `${Math.floor(months / 12)} г. ${months % 12} мес.` : '',
      salary: r.salary?.amount ? `${Number(r.salary.amount).toLocaleString('ru-RU')} ${r.salary.currency === 'RUR' ? '₽' : r.salary.currency}` : '',
      photo: r.photo?.medium || r.photo?.['500'] || r.photo?.small || r.photo?.['100'] || '',
      lastJob: last ? [last.position, last.company].filter(Boolean).join(' · ') : '',
      url: r.alternate_url || '', updatedAt: r.updated_at || '',
    };
  });
}
