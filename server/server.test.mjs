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

test('push and pull, the last change wins whatever its revision', async () => {
  await post('/push', { syncId, note: note('n1', 5, '2026-10-08T10:00:00Z', 'phone') });
  // Another device, fewer edits so a lower revision, but changed later.
  await post('/push', { syncId, note: note('n1', 2, '2026-10-08T11:00:00Z', 'pc-later') });
  // A late push of an older edit must not undo it.
  await post('/push', { syncId, note: note('n1', 9, '2026-10-08T09:00:00Z', 'stale') });
  await post('/push', { syncId, note: note('n2', 1, '2026-10-08T09:00:00Z') });
  const all = await post('/pull', { syncId });
  assert.equal(all.body.notes.length, 2);
  assert.equal(all.body.notes.find((n) => n.id === 'n1').encrypted_payload, 'pc-later');
});

test('pull since returns what reached the server after it, even an old edit', async () => {
  const before = (await post('/pull', { syncId })).body.serverTime;
  await new Promise((r) => setTimeout(r, 5));
  // Edited long ago on a device that was offline, pushed only now.
  await post('/push', { syncId, note: note('n4', 1, '2026-10-01T08:00:00Z', 'late') });
  const since = await post('/pull', { syncId, since: before });
  assert.deepEqual(since.body.notes.map((n) => n.id), ['n4']);
  await new Promise((r) => setTimeout(r, 5));
  const again = await post('/pull', { syncId, since: since.body.serverTime });
  assert.equal(again.body.notes.length, 0);
});

test('a push without ciphertext is refused', async () => {
  const r = await post('/push', { syncId, note: { id: 'n3', revision: 1 } });
  assert.equal(r.status, 400);
});

test.after(() => {
  server.closeAllConnections();
  server.close();
});
