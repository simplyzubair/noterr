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

- GitHub Actions builds the Windows app only. It holds no signing secrets.
- The Android app is built and signed on Zubair's PC, with keys pulled from Infisical: `infisical run --env=prod -- <build command>`. GitHub can't reach Infisical (Tailscale only), and Coolify runs web apps, not Android builds, so the PC does it.
- The signed APK is then uploaded to the GitHub release.
- Release steps: bump `version:` in `pubspec.yaml` and `MyAppVersion` in `installer/noterr.iss`, push, push tag `vX.Y.Z`, wait for CI to publish the release, then run `.\scripts\release-android.ps1 -Upload`. The script refuses to publish an APK not signed with the release key.
- Install or update the Windows app from a terminal: `.\scripts\noterr.ps1 install`.

## Hosting

- Noterr is a Windows and Android app, so the app itself is never hosted.
- Any server part (for example the sync backend or the website) goes on Contabo through Coolify. It is only open to the internet through nginx with HTTPS.
- Coolify gets its secrets from Infisical with `/opt/infisical/scripts/sync-coolify.sh noterr`.
- Website: Coolify app `noterr-website` (UUID `jcbbcuwysgecglkaleuazlyd`), built from `website/Dockerfile`, port mapping `127.0.0.1:3003:80` so only nginx can reach it. Host nginx config: `deploy/nginx/noterr.skillsgeek.com.conf`. HTTPS by `certbot --nginx`, same as the other sites.

## How to work

- Do not touch other apps on Contabo or the NAS.
- Ask before deleting or moving anything. Say exactly what, and from where to where.
- One step at a time.
