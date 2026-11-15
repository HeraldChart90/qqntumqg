import test from 'node:test';
import assert from 'node:assert/strict';
import { parseLooseJSON } from '../src/util.js';

test('parses fenced JSON', () => {
  assert.deepEqual(parseLooseJSON('```json\n{"a":1}\n```'), { a: 1 });
});
test('parses JSON with text around', () => {
  assert.deepEqual(parseLooseJSON('Вот ответ: {"a":[1,2]} готово'), { a: [1, 2] });
});
test('repairs a cut-off answer', () => {
  const value = parseLooseJSON('{"title":"Санузел","furniture":[{"name":"Унитаз","x":1},{"name":"Рако');
  assert.equal(value.title, 'Санузел');
  assert.equal(value.furniture[0].name, 'Унитаз');
});
