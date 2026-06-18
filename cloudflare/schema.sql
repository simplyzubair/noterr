create table if not exists noterr_profiles (
  sync_id text primary key,
  vault_salt text not null,
  created_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  updated_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
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
  updated_at text not null default (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  primary key (sync_id, id)
);

create index if not exists idx_noterr_notes_sync_updated
on noterr_notes(sync_id, updated_at desc);
