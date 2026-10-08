// Run: NODE_ENV=test DATA_DIR=<tmp> node --test server/server.test.mjs
// (Node 22 needs --experimental-sqlite as well.)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';

const { handle } = await import('./server.mjs');
const server = createServer((req, res) =>
  handle(req, res).catch((e) => {
    res.writeHead(500);
    res.end(JSON.stringify({ error: String(e) }));
  }),
);
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}`;
const post = async (path, body) => {
  const r = await fetch(base + path, { method: 'POST', body: JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
};
const syncId = 'a'.repeat(40);
const note = (id, revision, updatedAt, payload = 'x') => ({
  id, encrypted_payload: payload, nonce: 'n', mac: 'm', revision,
  device_id: 'd', updated_at: updatedAt, deleted_at: null,
});

test('health', async () => {
  const r = await fetch(base + '/health');
  assert.equal((await r.json()).ok, true);
});

test('first profile stores the salt, later calls keep it', async () => {
  assert.equal((await post('/profile', { syncId })).status, 400);
  const a = await post('/profile', { syncId, vaultSalt: 'salt-1' });
  assert.equal(a.body.vaultSalt, 'salt-1');
  const b = await post('/profile', { syncId, vaultSalt: 'salt-2' });
  assert.equal(b.body.vaultSalt, 'salt-1');
});

test('rejects bad ids and unknown profiles', async () => {
  assert.equal((await post('/pull', { syncId: 'nope' })).status, 400);
  assert.equal((await post('/pull', { syncId: 'b'.repeat(40) })).status, 404);
});

test('push and pull, newer revision wins, older is ignored', async () => {
  await post('/push', { syncId, note: note('n1', 2, '2026-10-08T10:00:00Z', 'v2') });
  await post('/push', { syncId, note: note('n1', 1, '2026-10-08T11:00:00Z', 'v1-stale') });
  await post('/push', { syncId, note: note('n2', 1, '2026-10-08T09:00:00Z') });
  const all = await post('/pull', { syncId });
  assert.equal(all.body.notes.length, 2);
  assert.equal(all.body.notes.find((n) => n.id === 'n1').encrypted_payload, 'v2');

  await post('/push', { syncId, note: note('n1', 3, '2026-10-08T12:00:00Z', 'v3') });
  const since = await post('/pull', { syncId, since: '2026-10-08T10:30:00Z' });
  assert.deepEqual(since.body.notes.map((n) => n.id), ['n1']);
  assert.equal(since.body.notes[0].encrypted_payload, 'v3');
});

test('a push without ciphertext is refused', async () => {
  const r = await post('/push', { syncId, note: { id: 'n3', revision: 1 } });
  assert.equal(r.status, 400);
});

test.after(() => {
  server.closeAllConnections();
  server.close();
});
