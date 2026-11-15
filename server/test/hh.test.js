// hh.ru flow against a fake api.hh.ru: connect, publish a work order, responses, chat.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import fs from 'node:fs';

const FAKE = 18_901, PORT = 18_902;
const log = [];
let posted = null;
function fake() {
  return http.createServer(async (req, res) => {
    let body = ''; for await (const c of req) body += c;
    const url = new URL(req.url, 'http://x');
    log.push({ m: req.method, p: url.pathname, ua: req.headers['hh-user-agent'], auth: req.headers.authorization, body });
    const json = (code, obj, headers = {}) => { res.writeHead(code, { 'Content-Type': 'application/json', ...headers }); res.end(JSON.stringify(obj)); };
    if (url.pathname === '/token') return json(200, { access_token: 'AT', refresh_token: 'RT', expires_in: 1209600 });
    if (url.pathname === '/me') return json(200, { employer: { id: '13089221', name: 'АртСтрой' }, manager: { id: '16969774' } });
    if (url.pathname === '/webhook/subscriptions' && req.method === 'GET') return json(200, { items: [] });
    if (url.pathname === '/webhook/subscriptions' && req.method === 'POST') return json(201, { id: 'w1' });
    if (url.pathname === '/suggests/areas') return json(200, { items: [{ id: '237', text: 'Сочи' }] });
    if (url.pathname === '/professional_roles') return json(200, { categories: [{ name: 'Рабочий персонал', roles: [{ id: '1', name: 'Бухгалтер' }, { id: '79', name: 'Маляр, штукатур' }, { id: '27', name: 'Строитель' }] }, { name: 'Строительство', roles: [{ id: '5', name: 'Инженер-строитель' }] }] });
    if (url.pathname.endsWith('/services/available_publications')) return json(200, { publication_variants: [
      { appearance: { title: 'Стандарт' }, available_publications_count: 3, suitable_packages: [{ employer_service_id: 'pkg1', invalid: false, count: 3 }], vacancy_properties: { required: [{ property_type: 'HH_STANDARD' }] } },
      { appearance: { title: 'Бесплатная' }, available_publications_count: 1, suitable_packages: [], vacancy_properties: { required: [{ property_type: 'HH_FREE' }] } },
    ] });
    if (url.pathname === '/resumes') return json(200, { items: [{ id: 'r1', first_name: 'Олег', last_name: 'Ким', title: 'Плиточник', area: { name: 'Сочи' }, age: 38, total_experience: { months: 100 }, salary: { amount: 120000, currency: 'RUR' }, photo: { medium: 'https://img.hh.ru/r1.jpg' }, alternate_url: 'https://hh.ru/resume/r1', experience: [{ position: 'Плиточник', company: 'СК Юг' }] }] });
    if (url.pathname === '/vacancies' && req.method === 'GET') return json(200, { items: [{ id: '42', name: 'Плиточник', employer: { name: 'СтройДом' }, area: { name: 'Сочи' }, salary_range: { from: 80000, to: 120000, currency: 'RUR' }, alternate_url: 'https://hh.ru/vacancy/42', published_at: '2026-10-24T10:00:00+0300', snippet: { responsibility: 'Укладка <highlighttext>плитки</highlighttext>' } }] });
    if (url.pathname === '/vacancies' && req.method === 'POST') { posted = JSON.parse(body); return json(201, { id: '555' }, { Location: '/vacancies/555' }); }
    if (url.pathname === '/vacancies/555') return json(200, { id: '555', approved: true, archived: false });
    if (url.pathname === '/negotiations') return json(200, { collections: [{ id: 'response', url: `http://127.0.0.1:${FAKE}/negotiations/response?vacancy_id=555` }] });
    if (url.pathname === '/negotiations/response') return json(200, { items: [{ id: 'n1', chat_id: 777, created_at: '2026-10-23T10:00:00+0300', counters: { unread_messages: 1 }, state: { name: 'Отклик' },
      resume: { first_name: 'Иван', last_name: 'Петров', title: 'Плиточник', area: { name: 'Сочи' }, total_experience: { months: 62 }, contact: [{ value: '+7999' }], age: 34 } }] });
    if (url.pathname === '/common/chats/777/messages' && req.method === 'GET') return json(200, { vacancy_id: '555', chat_states: { write_message_state: { allowed: true } }, messages: [
      { id: 'm1', creation_time: '2026-10-23T10:01:00+0300', payload: { text: 'Готов взяться' }, sender_display_info: { role: 'APPLICANT', name: 'Иван' } }] });
    if (url.pathname === '/common/chats/777/messages' && req.method === 'POST') return json(201, { id: 'm2' });
    if (url.pathname === '/common/chats/888/messages') return json(200, { vacancy_id: '999', messages: [] });
    json(404, { errors: [{ type: 'not_found' }] });
  }).listen(FAKE);
}

test('hh.ru integration', async (t) => {
  fs.rmSync('./data-hh', { recursive: true, force: true });
  const server = fake();
  const child = spawn(process.execPath, ['src/index.js'], { env: { ...process.env, PORT: String(PORT), DATA_DIR: './data-hh',
    HH_API: `http://127.0.0.1:${FAKE}`, HH_AUTHORIZE_URL: `http://127.0.0.1:${FAKE}/oauth/authorize`,
    HH_CLIENT_ID: 'cid', HH_CLIENT_SECRET: 'secret', HH_REDIRECT_URI: 'https://example.ru/v1/auth/hh/callback', HH_ADMIN_KEY: 'admin-key-123',
    PUBLIC_URL: 'https://example.ru', HH_USER_AGENT: 'ArtStroy/1.0 (test@example.ru)' }, stdio: 'pipe' });
  t.after(() => { child.kill(); server.close(); fs.rmSync('./data-hh', { recursive: true, force: true }); });
  await new Promise((r) => child.stdout.once('data', r));
  const base = `http://127.0.0.1:${PORT}`;
  const H = { 'X-Install-ID': 'install-0123456789abcd', 'Content-Type': 'application/json' };

  // wrong admin key
  assert.equal((await fetch(`${base}/v1/auth/hh/start?key=bad`, { redirect: 'manual' })).status, 403);
  // connect
  const start = await fetch(`${base}/v1/auth/hh/start?key=admin-key-123`, { redirect: 'manual' });
  assert.equal(start.status, 302);
  const state = new URL(start.headers.get('location')).searchParams.get('state');
  assert.equal(new URL(start.headers.get('location')).searchParams.get('role'), 'employer');
  const cb = await fetch(`${base}/v1/auth/hh/callback?code=CODE&state=${state}`);
  assert.equal(cb.status, 200);
  assert.match(await cb.text(), /АртСтрой/);
  assert.ok(log.some((l) => l.p === '/webhook/subscriptions' && l.m === 'POST' && l.body.includes('CHAT_MESSAGE_CREATED')));
  assert.ok(log.every((l) => l.p === '/token' || l.ua === 'ArtStroy/1.0 (test@example.ru)'));

  // publish (free tariff preferred, not the paid one)
  const pub = await (await fetch(`${base}/v1/hh/vacancies`, { method: 'POST', headers: H, body: JSON.stringify({ orderId: 'ord-1', category: 'Ремонт и отделка', city: 'Сочи, Адлер', details: 'Уложить плитку <b>20 м²</b>\nЗатирка', budget: '150 000 ₽' }) })).json();
  assert.equal(pub.vacancyId, '555');
  assert.deepEqual(posted.vacancy_properties, { properties: [{ property_type: 'HH_FREE' }] });
  assert.equal(posted.employer_service_id, undefined);
  assert.deepEqual(posted.professional_roles, [{ id: '79' }]);
  assert.equal(posted.employment_form.id, 'PROJECT');
  assert.match(posted.description, /&lt;b&gt;20/);
  const token = pub.token;

  // responses: no contacts / age leak
  const r = await (await fetch(`${base}/v1/hh/orders/ord-1/responses`, { headers: { ...H, 'X-HH-Order-Token': token } })).json();
  assert.equal(r.applicants[0].name, 'Иван П.');
  assert.equal(r.applicants[0].chatId, '777');
  assert.equal(r.applicants[0].experience, '5 г. 2 мес.');
  assert.ok(!JSON.stringify(r).includes('+7999'));
  // wrong token
  assert.equal((await fetch(`${base}/v1/hh/orders/ord-1/responses`, { headers: { ...H, 'X-HH-Order-Token': 'x' } })).status, 403);

  // chat
  const m = await (await fetch(`${base}/v1/hh/orders/ord-1/chats/777/messages`, { headers: { ...H, 'X-HH-Order-Token': token } })).json();
  assert.equal(m.messages[0].text, 'Готов взяться');
  assert.equal(m.messages[0].fromClient, false);
  const sent = await fetch(`${base}/v1/hh/orders/ord-1/chats/777/messages`, { method: 'POST', headers: { ...H, 'X-HH-Order-Token': token }, body: JSON.stringify({ text: 'Когда сможете начать?' }) });
  assert.equal(sent.status, 200);
  assert.ok(log.some((l) => l.p === '/common/chats/777/messages' && l.m === 'POST' && JSON.parse(l.body).idempotency_key));
  // market search
  const market = await (await fetch(`${base}/v1/market/vacancies?board=hh&text=плитка`, { headers: H })).json();
  assert.equal(market.items[0].title, 'Плиточник');
  assert.equal(market.items[0].snippet, 'Укладка плитки');
  assert.match(market.items[0].salary, /80/);
  // resumes: owner only
  assert.equal((await fetch(`${base}/v1/market/resumes?board=hh`, { headers: H })).status, 403);
  const rs = await (await fetch(`${base}/v1/market/resumes?board=hh&text=плиточник`, { headers: { ...H, 'X-Admin-Key': 'admin-key-123' } })).json();
  assert.equal(rs.items[0].photo, 'https://img.hh.ru/r1.jpg');
  assert.equal(rs.items[0].experience, '8 г. 4 мес.');
  assert.equal(rs.items[0].lastJob, 'Плиточник · СК Юг');
  // chat of another vacancy is refused
  assert.equal((await fetch(`${base}/v1/hh/orders/ord-1/chats/888/messages`, { headers: { ...H, 'X-HH-Order-Token': token } })).status, 403);
});
