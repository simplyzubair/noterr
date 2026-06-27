const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json',
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET,POST,OPTIONS',
      'access-control-allow-headers': 'content-type',
    },
  });

const bad = (message, status = 400) => json({ error: message }, status);
const nowIso = () => new Date().toISOString();
const validSyncId = (value) =>
  typeof value === 'string' && /^[a-f0-9]{40}$/.test(value);

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

async function getProfile(env, syncId) {
  return await env.DB.prepare(
    'select sync_id, vault_salt from noterr_profiles where sync_id = ?',
  )
    .bind(syncId)
    .first();
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return json({ ok: true });
    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return json({ ok: true, service: 'noterr-sync', backend: 'cloudflare-d1' });
    }

    if (request.method !== 'POST') return bad('Use POST.', 405);
    const body = await readJson(request);
    if (!body) return bad('Invalid JSON.');

    const syncId = body.syncId;
    if (!validSyncId(syncId)) return bad('Invalid syncId.');

    if (url.pathname === '/profile') {
      let profile = await getProfile(env, syncId);
      if (!profile) {
        const salt =
          typeof body.vaultSalt === 'string' && body.vaultSalt.length > 0
            ? body.vaultSalt
            : null;
        if (!salt) return bad('vaultSalt is required for first unlock.');
        const t = nowIso();
        await env.DB.prepare(
          'insert into noterr_profiles (sync_id, vault_salt, created_at, updated_at) values (?, ?, ?, ?)',
        )
          .bind(syncId, salt, t, t)
          .run();
        profile = { sync_id: syncId, vault_salt: salt };
      }
      return json({ syncId: profile.sync_id, vaultSalt: profile.vault_salt });
    }

    const profile = await getProfile(env, syncId);
    if (!profile) return bad('Unknown sync profile.', 404);

    if (url.pathname === '/pull') {
      const rows = await env.DB.prepare(
        'select id, encrypted_payload, nonce, mac, payload_version, revision, device_id, deleted_at, updated_at from noterr_notes where sync_id = ? order by updated_at desc',
      )
        .bind(syncId)
        .all();
      return json({ notes: rows.results || [], serverTime: nowIso() });
    }

    if (url.pathname === '/push') {
      const note = body.note;
      if (!note || typeof note.id !== 'string') return bad('note is required.');
      const t = nowIso();
      const clientUpdatedAt =
        typeof note.updated_at === 'string' && note.updated_at.length > 0
          ? note.updated_at
          : t;
      await env.DB.prepare(
        'insert into noterr_notes (id, sync_id, encrypted_payload, nonce, mac, payload_version, revision, device_id, deleted_at, updated_at) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) on conflict(sync_id, id) do update set encrypted_payload = excluded.encrypted_payload, nonce = excluded.nonce, mac = excluded.mac, payload_version = excluded.payload_version, revision = excluded.revision, device_id = excluded.device_id, deleted_at = excluded.deleted_at, updated_at = excluded.updated_at where excluded.revision > noterr_notes.revision or (excluded.revision = noterr_notes.revision and excluded.updated_at > noterr_notes.updated_at)',
      )
        .bind(
          note.id,
          syncId,
          note.encrypted_payload,
          note.nonce,
          note.mac,
          note.payload_version || 1,
          note.revision || 1,
          note.device_id || '',
          note.deleted_at || null,
          clientUpdatedAt,
        )
        .run();
      return json({ ok: true, updatedAt: clientUpdatedAt, serverTime: t });
    }

    return bad('Not found.', 404);
  },
};
