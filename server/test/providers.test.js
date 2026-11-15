// End‑to‑end with fake GigaChat and Yandex APIs: streaming, JSON via function call, fallback, vision upload.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';

const FAKE = 18_801, PORT = 18_802;
const headers = { 'X-Install-ID': 'abcdef0123456789abcd', 'Content-Type': 'application/json' };
const seen = [];

function fakeServer() {
  return http.createServer(async (req, res) => {
    let body = '';
    for await (const c of req) body += c;
    seen.push({ url: req.url, headers: req.headers, body: body.slice(0, 300) });
    if (req.url === '/oauth') { res.end(JSON.stringify({ access_token: 'tok', expires_at: Date.now() + 1_800_000 })); return; }
    if (req.url === '/giga/files') { res.end(JSON.stringify({ id: 'file-1' })); return; }
    if (req.url === '/giga/chat/completions') {
      const json = JSON.parse(body);
      if (json.messages.some((m) => m.content === 'FAIL')) { res.writeHead(500); res.end('{}'); return; }
      if (json.functions) {
        res.end(JSON.stringify({ choices: [{ message: { function_call: { name: json.functions[0].name, arguments: { title: 'Санузел', ok: true } } } }] }));
        return;
      }
      if (json.stream) {
        res.writeHead(200, { 'Content-Type': 'text/event-stream' });
        res.write('data: {"choices":[{"delta":{"content":"При"}}]}\n\n');
        res.write('data: {"choices":[{"delta":{"content":"вет"}}]}\n\n');
        res.end('data: [DONE]\n\n');
        return;
      }
      res.end(JSON.stringify({ choices: [{ message: { content: `giga:${json.messages.at(-1).attachments ? 'with-photo' : 'text'}` } }] }));
      return;
    }
    if (req.url === '/ya/chat/completions') {
      res.end(JSON.stringify({ choices: [{ message: { content: 'yandex-answer' } }] }));
      return;
    }
    res.writeHead(404); res.end('{}');
  }).listen(FAKE);
}

test('providers through the server', async (t) => {
  const fake = fakeServer();
  const child = spawn(process.execPath, ['src/index.js'], {
    env: { ...process.env, PORT: String(PORT), DATA_DIR: './data-test2', AI_PROVIDERS: 'gigachat,yandex',
      GIGACHAT_AUTH_KEY: 'x', GIGACHAT_OAUTH_URL: `http://127.0.0.1:${FAKE}/oauth`, GIGACHAT_BASE: `http://127.0.0.1:${FAKE}/missing,http://127.0.0.1:${FAKE}/giga`,
      YANDEX_API_KEY: 'k', YANDEX_FOLDER_ID: 'b1folder', YANDEX_BASE: `http://127.0.0.1:${FAKE}/ya` },
    stdio: 'pipe',
  });
  t.after(() => { child.kill(); fake.close(); });
  await new Promise((resolve) => child.stdout.once('data', resolve));
  const base = `http://127.0.0.1:${PORT}`;
  const post = (path, body) => fetch(`${base}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });

  // plain answer (first base 404 → second base is used)
  let r = await (await post('/v1/ai/chat', { system: 's', messages: [{ role: 'user', text: 'Привет' }] })).json();
  assert.equal(r.text, 'giga:text');

  // photo goes as an uploaded file
  r = await (await post('/v1/ai/chat', { messages: [{ role: 'user', text: 'Что на фото', image: 'A'.repeat(200) }] })).json();
  assert.equal(r.text, 'giga:with-photo');

  // streaming
  const stream = await (await post('/v1/ai/chat', { stream: true, messages: [{ role: 'user', text: 'Привет' }] })).text();
  assert.match(stream, /"delta":"При"/);
  assert.match(stream, /"done":true/);

  // structured JSON via function call
  r = await (await post('/v1/ai/json', { name: 'design proposal', schema: { type: 'object' }, messages: [{ role: 'user', text: 'план' }] })).json();
  assert.deepEqual(r.json, { title: 'Санузел', ok: true });
  assert.ok(seen.some((s) => s.body.includes('"name":"design_proposal"')));

  // GigaChat fails → Yandex answers, with Api-Key auth and folder header
  r = await (await post('/v1/ai/chat', { messages: [{ role: 'user', text: 'FAIL' }] })).json();
  assert.equal(r.text, 'yandex-answer');
  const ya = seen.find((s) => s.url === '/ya/chat/completions');
  assert.equal(ya.headers.authorization, 'Api-Key k');
  assert.match(ya.body, /gpt:\/\/b1folder\/yandexgpt\/latest/);

  // capabilities
  const caps = await (await fetch(`${base}/v1/ai/capabilities`, { headers })).json();
  assert.deepEqual(caps.providers, ['gigachat', 'yandex']);
  assert.deepEqual(caps.imageEdit, []);
});
