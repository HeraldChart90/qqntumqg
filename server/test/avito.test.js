// Avito flow against a fake api.avito.ru: connect, publish a work order, applications, chat.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import fs from 'node:fs';

const FAKE = 18_951, PORT = 18_952;
const log = [];
let posted = null;
function fake() {
  return http.createServer(async (req, res) => {
    let body = ''; for await (const c of req) body += c;
    const url = new URL(req.url, 'http://x');
    log.push({ m: req.method, p: url.pathname, q: url.search, body });
    const json = (code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };
    if (url.pathname === '/token') return json(200, { access_token: 'AT', refresh_token: 'RT', expires_in: 86400 });
    if (url.pathname === '/core/v1/accounts/self') return json(200, { id: 4242, name: 'АртСтрой' });
    if (url.pathname === '/messenger/v3/webhook') return json(200, { ok: true });
    if (url.pathname === '/job/v1/applications/webhook') return json(200, { ok: true });
    if (url.pathname === '/job/v2/vacancy/dict/business_area') return json(200, [{ id: 1, name: 'Продажи' }, { id: 7, name: 'Строительство' }]);
    if (url.pathname === '/job/v2/vacancy/dict/profession') return json(200, [{ id: 10, name: 'Повар' }, { id: 55, name: 'Плиточник' }]);
    if (url.pathname === '/job/v1/resumes/') return json(200, { resumes: [{ id: 77, title: 'Сантехник', location: { title: 'Сочи' }, total_experience: 12, salary: 90000 }, { id: 78, title: 'Курьер', location: { title: 'Казань' } }] });
    if (url.pathname === '/job/v2/resumes/77') return json(200, { photos: [{ url: 'https://img.avito.st/77.jpg' }] });
    if (url.pathname === '/job/v2/vacancies' && req.method === 'GET') return json(200, { vacancies: [
      { title: 'Плиточник на объект', companyName: 'Ремонт Юг', addressDetails: { city: 'Сочи' }, link: 'https://www.avito.ru/sochi/vakansii/1', profession: 'Плиточник' },
      { title: 'Повар', companyName: 'Кафе', addressDetails: { city: 'Москва' }, link: 'https://www.avito.ru/moskva/vakansii/2' }] });
    if (url.pathname === '/job/v1/vacancies' && req.method === 'POST') { posted = JSON.parse(body); return json(201, { id: '3001', url: 'https://www.avito.ru/vac/3001' }); }
    if (url.pathname === '/job/v1/applications/get_ids') return json(200, { applies: [{ id: 'a1' }] });
    if (url.pathname === '/job/v1/applications/get_by_ids') return json(200, { applies: [{ id: 'a1', vacancy_id: 3001, is_viewed: false, created_at: '2026-10-25T10:00:00Z',
      applicant: { data: { full_name: { first_name: 'Пётр', last_name: 'Сидоров' }, birthday: '1990-01-01' } }, contacts: { chat: { value: 'u2i-1-2' }, phones: [{ value: '79990001122' }] },
      enriched_properties: { experience: { value: '7' } } }] });
    if (url.pathname === '/messenger/v2/accounts/4242/chats/u2i-1-2') return json(200, { context: { value: { id: 3001 } }, users: [{ id: 4242, name: 'АртСтрой' }, { id: 9, name: 'Пётр' }] });
    if (url.pathname === '/messenger/v2/accounts/4242/chats/u2i-9-9') return json(200, { context: { value: { id: 9999 } } });
    if (url.pathname === '/messenger/v3/accounts/4242/chats/u2i-1-2/messages/') return json(200, { messages: [{ id: 'm1', direction: 'in', created: 1761386400, content: { text: 'Здравствуйте, готов' } }] });
    if (url.pathname === '/messenger/v1/accounts/4242/chats/u2i-1-2/read') return json(200, { ok: true });
    if (url.pathname === '/messenger/v1/accounts/4242/chats/u2i-1-2/messages') return json(200, { id: 'm2' });
    json(404, { error: { message: 'not found' } });
  }).listen(FAKE);
}

test('avito integration', async (t) => {
  fs.rmSync('./data-avito', { recursive: true, force: true });
  const server = fake();
  const child = spawn(process.execPath, ['src/index.js'], { env: { ...process.env, PORT: String(PORT), DATA_DIR: './data-avito',
    AVITO_API: `http://127.0.0.1:${FAKE}`, AVITO_AUTHORIZE_URL: `http://127.0.0.1:${FAKE}/oauth`,
    AVITO_CLIENT_ID: 'cid', AVITO_CLIENT_SECRET: 'sec', HH_ADMIN_KEY: 'admin-key-123', PUBLIC_URL: 'https://example.ru' }, stdio: 'pipe' });
  t.after(() => { child.kill(); server.close(); fs.rmSync('./data-avito', { recursive: true, force: true }); });
  await new Promise((r) => child.stdout.once('data', r));
  const base = `http://127.0.0.1:${PORT}`;
  const H = { 'X-Install-ID': 'install-0123456789abcd', 'Content-Type': 'application/json' };

  const start = await fetch(`${base}/v1/auth/avito/start?key=admin-key-123`, { redirect: 'manual' });
  assert.equal(start.status, 302);
  const loc = new URL(start.headers.get('location'));
  assert.match(loc.searchParams.get('scope'), /messenger:write/);
  const cb = await fetch(`${base}/v1/auth/avito/callback?code=C&state=${loc.searchParams.get('state')}`);
  assert.equal(cb.status, 200);
  assert.ok(log.some((l) => l.p === '/token' && l.body.includes('grant_type=authorization_code') && l.body.includes('client_secret=sec')));
  assert.ok(log.some((l) => l.p === '/messenger/v3/webhook'));

  const pub = await (await fetch(`${base}/v1/avito/vacancies`, { method: 'POST', headers: H, body: JSON.stringify({ orderId: 'o-7', category: 'Ремонт и отделка', city: 'Адлер', details: 'Плитка в санузле', budget: '90 000 ₽' }) })).json();
  assert.equal(pub.vacancyId, '3001');
  assert.equal(posted.billing_type, 'package');
  assert.equal(posted.business_area, 7);
  assert.equal(posted.profession, 55);
  assert.equal(posted.address, 'Сочи, Адлер');
  assert.ok(posted.name.length <= 50);
  assert.deepEqual(posted.construction_work_type, ['finishingWork', 'repairWork']);

  const r = await (await fetch(`${base}/v1/avito/orders/o-7/responses`, { headers: { ...H, 'X-Order-Token': pub.token } })).json();
  assert.equal(r.applicants[0].name, 'Пётр С.');
  assert.equal(r.applicants[0].chatId, 'u2i-1-2');
  assert.equal(r.applicants[0].experience, '7 г.');
  assert.ok(!JSON.stringify(r).includes('7999') && !JSON.stringify(r).includes('1990'));

  const m = await (await fetch(`${base}/v1/avito/orders/o-7/chats/u2i-1-2/messages`, { headers: { ...H, 'X-Order-Token': pub.token } })).json();
  assert.equal(m.messages[0].text, 'Здравствуйте, готов');
  assert.equal(m.messages[0].name, 'Пётр');
  const s = await fetch(`${base}/v1/avito/orders/o-7/chats/u2i-1-2/messages`, { method: 'POST', headers: { ...H, 'X-Order-Token': pub.token }, body: JSON.stringify({ text: 'Когда сможете?' }) });
  assert.equal(s.status, 200);
  assert.ok(log.some((l) => l.p === '/messenger/v1/accounts/4242/chats/u2i-1-2/messages' && JSON.parse(l.body).type === 'text'));
  assert.equal((await fetch(`${base}/v1/avito/orders/o-7/chats/u2i-9-9/messages`, { headers: { ...H, 'X-Order-Token': pub.token } })).status, 403);
  assert.equal((await fetch(`${base}/v1/avito/orders/o-7/responses`, { headers: { ...H, 'X-Order-Token': 'bad' } })).status, 403);
  const rs = await (await fetch(`${base}/v1/market/resumes?board=avito&text=сантехник`, { headers: { ...H, 'X-Admin-Key': 'admin-key-123' } })).json();
  assert.equal(rs.items.length, 1);
  assert.equal(rs.items[0].photo, 'https://img.avito.st/77.jpg');
  assert.equal(rs.items[0].salary.replace(/\s/g, ''), '90000₽');
  const market = await (await fetch(`${base}/v1/market/vacancies?board=avito&text=плиточник`, { headers: H })).json();
  assert.equal(market.items.length, 1);
  assert.equal(market.items[0].company, 'Ремонт Юг');
});
