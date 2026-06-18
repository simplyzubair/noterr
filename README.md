# Noterr

Noterr is a local-first sticky note and daily task app for Windows and Android.

## Sync

Noterr now uses Cloudflare:

- Cloudflare Worker: small HTTP sync API.
- Cloudflare D1: encrypted database storage.
- The app encrypts notes before upload. The Worker never sees plaintext.

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
