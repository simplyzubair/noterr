// Noterr sync server, self-hosted on Contabo (Coolify). Same API as the old
// Cloudflare Worker in cloudflare/: POST /profile, /pull, /push, GET /health.
//
// It only ever stores encrypted notes: devices encrypt with a key derived
// from the user's PIN before sending. The sync id is a hash of the PIN, so
// the server never sees the PIN either.
//
// Node's built-in SQLite, no dependencies. Data lives in $DATA_DIR.
import { createServer } from 'node:http';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const PORT = Number(process.env.PORT || 8080);
const DATA_DIR = process.env.DATA_DIR || '/data';
const MAX_BODY = 5 * 1024 * 1024;

mkdirSync(DATA_DIR, { recursive: true });
// Exported so the module keeps a strong reference: prepared statements alone
// don't keep the connection alive, and a collected connection finalizes them
// ("statement has been finalized").
export const db = new DatabaseSync(join(DATA_DIR, 'noterr-sync.db'));
db.exec(`
  pragma journal_mode = wal;
  create table if not exists noterr_profiles (
    sync_id text primary key,
    vault_salt text not null,
    created_at text not null,
    updated_at text not null
  );
  create table if not exists noterr_notes (
    id text not null,
    sync_id text not null,
    encrypted_payload text not null,
    nonce text not null,
    mac text not null,
    payload_version integer not null default 1,
    revision integer not null default 1,
    device_id text not null default '',
    deleted_at text,
    updated_at text not null,
    primary key (sync_id, id)
  );
  create index if not exists idx_noterr_notes_sync_updated
    on noterr_notes(sync_id, updated_at desc);
`);
// synced_at is when the server received the note (server clock). updated_at
// is the device's clock at the edit, which can be minutes old when a push is
// retried, so "what changed since my last pull" must not use it.
if (!db.prepare('pragma table_info(noterr_notes)').all().some((c) => c.name === 'synced_at')) {
  db.exec(`
    alter table noterr_notes add column synced_at text not null default '';
    update noterr_notes set synced_at = updated_at where synced_at = '';
  `);
}
db.exec('create index if not exists idx_noterr_notes_sync_synced on noterr_notes(sync_id, synced_at)');

const getProfile = db.prepare('select sync_id, vault_salt from noterr_profiles where sync_id = ?');
const insertProfile = db.prepare(
  'insert into noterr_profiles (sync_id, vault_salt, created_at, updated_at) values (?, ?, ?, ?)',
);
const pullAll = db.prepare(
  'select id, encrypted_payload, nonce, mac, payload_version, revision, device_id, deleted_at, updated_at from noterr_notes where sync_id = ? order by updated_at desc',
);
const pullSince = db.prepare(
  'select id, encrypted_payload, nonce, mac, payload_version, revision, device_id, deleted_at, updated_at from noterr_notes where sync_id = ? and synced_at >= ? order by updated_at desc',
);
// The last change wins: the later edit time, whichever device made it. Each
// device counts revisions on its own, so a revision can't order two devices.
const upsertNote = db.prepare(`
  insert into noterr_notes (id, sync_id, encrypted_payload, nonce, mac, payload_version, revision, device_id, deleted_at, updated_at, synced_at)
  values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  on conflict(sync_id, id) do update set
    encrypted_payload = excluded.encrypted_payload, nonce = excluded.nonce, mac = excluded.mac,
    payload_version = excluded.payload_version, revision = excluded.revision,
    device_id = excluded.device_id, deleted_at = excluded.deleted_at, updated_at = excluded.updated_at,
    synced_at = excluded.synced_at
  where excluded.updated_at > noterr_notes.updated_at
     or (excluded.updated_at = noterr_notes.updated_at and excluded.revision > noterr_notes.revision)
`);

const nowIso = () => new Date().toISOString();
// Edit times are compared as text, so store them all in one shape.
const isoOrNull = (v) => {
  const ms = typeof v === 'string' ? Date.parse(v) : NaN;
  return Number.isNaN(ms) ? null : new Date(ms).toISOString();
};
const validSyncId = (v) => typeof v === 'string' && /^[a-f0-9]{40}$/.test(v);
const str = (v) => (typeof v === 'string' ? v : null);

function send(res, status, data) {
  res.writeHead(status, {
    'content-type': 'application/json',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'content-type',
  });
  res.end(JSON.stringify(data));
}

function readBody(req) {
  return new Promise((resolve) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        resolve(null);
        req.destroy();
      } else chunks.push(c);
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        resolve(null);
      }
    });
    req.on('error', () => resolve(null));
  });
}

export async function handle(req, res) {
  const path = new URL(req.url, 'http://x').pathname.replace(/\/+$/, '') || '/';
  if (req.method === 'OPTIONS') return send(res, 200, { ok: true });
  if (path === '/health') return send(res, 200, { ok: true, service: 'noterr-sync', backend: 'sqlite' });
  if (req.method !== 'POST') return send(res, 405, { error: 'Use POST.' });

  const body = await readBody(req);
  if (!body || typeof body !== 'object') return send(res, 400, { error: 'Invalid JSON.' });
  const syncId = body.syncId;
  if (!validSyncId(syncId)) return send(res, 400, { error: 'Invalid syncId.' });

  if (path === '/profile') {
    let profile = getProfile.get(syncId);
    if (!profile) {
      const salt = str(body.vaultSalt);
      if (!salt) return send(res, 400, { error: 'vaultSalt is required for first unlock.' });
      const t = nowIso();
      insertProfile.run(syncId, salt, t, t);
      profile = { sync_id: syncId, vault_salt: salt };
    }
    return send(res, 200, { syncId: profile.sync_id, vaultSalt: profile.vault_salt });
  }

  if (!getProfile.get(syncId)) return send(res, 404, { error: 'Unknown sync profile.' });

  if (path === '/pull') {
    // Read the clock first: a note stored while we read is then sent again
    // next time instead of being skipped.
    const serverTime = nowIso();
    const since = isoOrNull(body.since);
    const notes = since ? pullSince.all(syncId, since) : pullAll.all(syncId);
    return send(res, 200, { notes, serverTime });
  }

  if (path === '/push') {
    const n = body.note;
    if (!n || typeof n.id !== 'string') return send(res, 400, { error: 'note is required.' });
    if (!str(n.encrypted_payload) || !str(n.nonce) || !str(n.mac)) {
      return send(res, 400, { error: 'note is missing encrypted fields.' });
    }
    const t = nowIso();
    const updatedAt = isoOrNull(n.updated_at) || t;
    upsertNote.run(
      n.id, syncId, n.encrypted_payload, n.nonce, n.mac,
      Number(n.payload_version) || 1, Number(n.revision) || 1,
      str(n.device_id) || '', str(n.deleted_at), updatedAt, t,
    );
    return send(res, 200, { ok: true, updatedAt, serverTime: t });
  }

  return send(res, 404, { error: 'Not found.' });
}

if (process.env.NODE_ENV !== 'test') {
  createServer((req, res) => {
    handle(req, res).catch((e) => {
      console.error(e);
      if (!res.headersSent) send(res, 500, { error: 'Server error.' });
    });
  }).listen(PORT, () => console.log(`noterr-sync listening on ${PORT}, data in ${DATA_DIR}`));
}
