# Noterr

Noterr is a local-first sticky note and daily task app for Windows and Android.

## Plan Import

Plans stay behind the **More > Plans** area. Paste a structured plan or choose
a `.txt`/`.md` file, select its start and end dates, review the classification
and schedule, then activate it. Due tasks and habits appear in the existing
Today board, desktop sticky, and Android widget.

~~~text
Plan: August Health

Outcomes:
- Lose 1 kg

Daily:
- Walk 1 km Monday to Saturday

Weekly:
- Record weight every Sunday

Tasks:
- Buy walking shoes
~~~

Noterr classifies outcomes, projects, tasks, and habits but does not invent
goals. One-time tasks without dates are spread across the selected range.
Everything is shown for approval before activation.

## Sync

Noterr now uses Cloudflare:

- Cloudflare Worker: small HTTP sync API.
- Cloudflare D1: encrypted database storage.
- The app encrypts notes before upload. The Worker never sees plaintext.

The old Supabase project/schema is legacy only. The current Windows and
Android builds do not depend on hosted Supabase, so the hosted Supabase project
can pause without breaking Noterr sync.

## Setup

1. Deploy the sync Worker:

```powershell
.\Deploy-Cloudflare-Sync.bat
```

2. Copy the deployed `workers.dev` URL.
3. Save it locally:

```powershell
.\Configure-Sync.bat
```

4. Build release apps:

```powershell
.\Build-Sync-Release.ps1
```

## Useful Paths

- Windows install: `C:\Users\zubai\AppData\Local\Programs\Noterr\noterr.exe`
- Android APK: `C:\tmp\NoterrBuild\build\app\outputs\flutter-apk\app-release.apk`
- Worker source: `cloudflare/noterr-sync-worker.js`
- D1 schema: `cloudflare/schema.sql`

## Supabase Notes

- Legacy Supabase schema: `supabase/schema.sql`
- Future Supabase/Codex setup notes: `docs/SUPABASE.md`
