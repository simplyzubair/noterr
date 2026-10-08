# Noterr: rules for Claude

These add to the global rules in `~/.claude/CLAUDE.md`. This repo is public, so anything committed is published.

- Name: Noterr
- Website: noterr.skillsgeek.com, a download page with the latest Android APK and Windows installer (planned, not set up yet: no DNS record, no nginx site)

## Secrets

- All secrets live in Infisical, project `noterr` (ID `dc732f83-ec69-465d-9216-2d911d2db9d4`), env `prod` (https://contabo-sin-01.tail594efe.ts.net:8443, Tailscale only).
- Never put a secret in code, in a commit, or in GitHub.
- Zubair types the real values into Infisical. Claude only names the keys. When a secret is needed locally, write a script that asks for it. Never print it.
- Local files that hold secrets are gitignored: `android/key.properties` and `*.jks`. Never open or edit `android/key.properties` in the editor. Editing it once overwrote the signing password.
- Android signing key: `D:\noterr-release-key.jks`, with a backup on the NAS at `~/Backups/Noterr/keystore/`. If this file or its password is lost, Android updates can never be published again.
- Key names are listed in `.env.example` (empty values). Infisical holds the real ones.

## Releases

- Every push to `master` that changes the app is a release. CI sets the version to `<major>.<minor>` from `pubspec.yaml` plus the run number (for example `0.4.77`), builds Windows and Android, tags `vX.Y.Z` and publishes the release. Nobody bumps versions or pushes tags by hand. Only change `pubspec.yaml`'s major.minor for a bigger version jump. Pushes that only touch `*.md`, `website/`, `deploy/` or `.env.example` don't release.
- GitHub-hosted runners build Windows and hold no secrets.
- Android is built on Zubair's PC by a self-hosted runner (label `noterr-android`, folder `D:\Runners\noterr`, started at logon by the scheduled task "Noterr GitHub runner"). It runs `scripts/release-android.ps1 -Robot`, which logs in to Infisical as a machine identity saved (encrypted for the Windows user) by `scripts/ci/save-infisical-identity.ps1`. GitHub can't reach Infisical (Tailscale only), so the PC does it. If the PC is off, the Android job waits (up to 24 hours) and the release waits with it.
- The Android job never runs for pull requests, and the repo requires approval before running workflows from outside contributors, so no stranger's code runs on the PC. Keep it that way: the repo is public.
- Manual fallback: `.\scripts\release-android.ps1 -Upload` builds and uploads to the release for the version in `pubspec.yaml`. It refuses to publish an APK not signed with the release key.
- Installed apps check for a new release at start, every 3 hours and when brought back to the front. Windows installs silently after one click on Update; Android downloads in the app and shows the system Install button (one tap; Android requires it outside the Play Store).
- Install or update the Windows app on any PC with one line in PowerShell: `irm https://raw.githubusercontent.com/simplyzubair/noterr/master/scripts/install.ps1 | iex`. In the repo, `.\scripts\noterr.ps1 install|version|doctor|uninstall` does the same plus more.

## Hosting

- Noterr is a Windows and Android app, so the app itself is never hosted.
- Any server part (for example the sync backend or the website) goes on Contabo through Coolify. It is only open to the internet through nginx with HTTPS.
- Coolify gets its secrets from Infisical with `/opt/infisical/scripts/sync-coolify.sh noterr`.
- Website: Coolify app `noterr-website` (UUID `jcbbcuwysgecglkaleuazlyd`), built from `website/Dockerfile`, port mapping `127.0.0.1:3003:80` so only nginx can reach it. Host nginx config: `deploy/nginx/noterr.skillsgeek.com.conf`. HTTPS by `certbot --nginx`, same as the other sites.

## How to work

- Do not touch other apps on Contabo or the NAS.
- Ask before deleting or moving anything. Say exactly what, and from where to where.
- One step at a time.
