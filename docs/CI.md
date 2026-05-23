# Continuous Builds

GitHub Actions builds Noterr whenever code is pushed to `main`.

## Required GitHub Secrets

In GitHub, open:

`Settings -> Secrets and variables -> Actions -> New repository secret`

Add these secrets:

- `NOTERR_SUPABASE_URL`
- `NOTERR_SUPABASE_ANON_KEY`

Use the Noterr Supabase project values only.

If GitHub CLI is installed and signed in, run this from the project folder:

```powershell
.\Set-GitHub-Secrets.ps1
```

## Build Outputs

The workflow uploads these artifacts:

- `noterr-android-apks`
  - `app-arm64-v8a-release.apk` for most modern Android phones.
  - `app-armeabi-v7a-release.apk` for older Android phones.
  - `app-x86_64-release.apk` for Android emulators.
- `noterr-windows-release`
  - Zip of the Windows app folder.
- `noterr-windows-installer`
  - `NoterrSetup.exe`.

## Manual Build

Open the **Actions** tab, choose **Build Noterr**, then click
**Run workflow**.
