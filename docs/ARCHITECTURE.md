# Architecture

## Recommendation

Use Flutter for Windows and Android, with Supabase as the first sync backend.

Supabase is a strong fit because the free plan currently includes a Postgres database, Auth, Storage, and Realtime. It is also easier to migrate away from later than Firebase because the data model is relational and the sync code is isolated behind `RemoteSyncService`.

## Sync Model

Noterr is local-first:

- Each device keeps an encrypted local vault.
- Notes can be created and edited offline.
- When online, note envelopes are uploaded to Supabase.
- Supabase Realtime pushes remote changes to active devices.
- Conflict resolution is last-write-wins for version 1, using `updatedAt` plus a revision counter.

## Encryption Model

Noterr uses a separate sync passphrase, not the Supabase login password.

- Supabase Auth identifies the user.
- A public salt is stored in `noterr_profiles`.
- The user enters the same sync passphrase on each device.
- A 256-bit key is derived with PBKDF2-HMAC-SHA256.
- Notes are encrypted with AES-GCM before local storage and before upload.
- Supabase stores ciphertext, nonce, and MAC only.

This means server-side global search cannot read note contents. Search runs locally after unlock.

## Replaceable Backend

The app only talks to cloud sync through `RemoteSyncService`.

Future backends can implement the same interface:

- Supabase now.
- A custom API on DigitalOcean later.
- A NAS-hosted sync API later.

## Desktop Sticky Notes

The Flutter source includes pin/always-on-top state and desktop window hooks. Full separate floating note windows need the generated Windows runner plus the `window_manager` or multi-window plugin integration after Flutter is installed.

## Android Widgets

Flutter cannot render Android home-screen widgets by itself. The app includes widget data publishing through `home_widget`; the next native step is adding a Kotlin `AppWidgetProvider` and widget layouts once the Android runner exists.
