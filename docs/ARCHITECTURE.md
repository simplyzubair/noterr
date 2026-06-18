# Architecture

Noterr is a Flutter app for Windows and Android. It is local-first and syncs through a Cloudflare Worker backed by Cloudflare D1.

## Data Model

- Notes are stored locally in an encrypted vault.
- The sync passphrase derives both the local encryption key and a stable sync id.
- Cloudflare stores only encrypted note envelopes.
- The Worker API exposes `/profile`, `/pull`, `/push`, and `/health`.

## Cloud Sync

Cloudflare D1 tables:

- `noterr_profiles`: sync id and vault salt.
- `noterr_notes`: encrypted payload, nonce, MAC, revision, device id, and timestamps.

The Worker has no access to plaintext notes. It only upserts and returns encrypted blobs.

## Local Behavior

- Windows starts in tray and opens the daily sticky.
- Android app and widget use the same encrypted sync backend.
- Completed/deleted tasks do not carry forward.
- Notes and unfinished tasks carry forward into the next daily board.
