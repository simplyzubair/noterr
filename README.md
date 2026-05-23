# Noterr

Noterr is a Flutter sticky-note app planned for Windows desktop and Android. It is local-first, password encrypted, and designed to sync through Supabase now while keeping the sync layer replaceable for a NAS or DigitalOcean backend later.

## Current Build Direction

- One Flutter codebase for Windows and Android.
- Supabase Auth, Realtime, Postgres, and Storage for the first cloud sync target.
- End-to-end note encryption using a separate sync passphrase.
- Encrypted local vault for offline use.
- Sticky-note UX with colors, tags, checklists, reminders, attachments, archive, trash, search, pinning, and desktop floating-window hooks.
- Android widget bridge planned through `home_widget` plus native Android widget files after Flutter generates the Android platform folder.

## Setup

1. Install Flutter, Android Studio SDKs, and Visual Studio Build Tools with the Desktop C++ workload.
2. Run `flutter create --platforms=windows,android .` from this folder to generate platform runners.
3. Run `flutter pub get`.
4. Create a Supabase project and apply [supabase/schema.sql](supabase/schema.sql).
5. Run with:

```powershell
flutter run -d windows --dart-define=SUPABASE_URL="https://YOUR_PROJECT.supabase.co" --dart-define=SUPABASE_ANON_KEY="YOUR_ANON_KEY"
```

For local-only testing, omit the two `--dart-define` values.

## Build Artifacts

Windows installer and Android APK steps are in [docs/BUILD.md](docs/BUILD.md).
