#!/usr/bin/env bash
# Build and sign the Noterr Android APK on the NAS runner (Linux).
#
# Linux twin of scripts/release-android.ps1 -Robot. Signing keys come from
# Infisical (project noterr, env prod) through `infisical run`, so they never
# touch GitHub or the repo. The decoded keystore is deleted after the build,
# and the APK must carry the real release certificate.
#
# The Infisical robot login is read from $INFISICAL_IDENTITY_FILE
# (default /run/secrets/infisical.env, mounted into the runner container).
#
# Usage: scripts/release-android.sh [--version 0.4.90] [--build-number 190]
set -euo pipefail

DOMAIN='https://contabo-sin-01.tail594efe.ts.net:8443/api'
PROJECT='dc732f83-ec69-465d-9216-2d911d2db9d4'
# SHA-256 of the release certificate (public, not a secret). Any other value
# means the APK could not be installed over existing installs.
EXPECTED_CERT='a4baaed4a8c8427e0e2231fe72fca20db986e13082aeb39c6ae4d2b68e84dab1'
ID_FILE="${INFISICAL_IDENTITY_FILE:-/run/secrets/infisical.env}"

VERSION=''
BUILD_NUMBER=''
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PUBSPEC_VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1 | tr -d '[:space:]')"
[ -n "$VERSION" ] || VERSION="${PUBSPEC_VERSION%%+*}"
if [ -z "$BUILD_NUMBER" ]; then
  case "$PUBSPEC_VERSION" in *+*) BUILD_NUMBER="${PUBSPEC_VERSION##*+}" ;; *) BUILD_NUMBER=1 ;; esac
fi
echo "version : $VERSION"

[ -r "$ID_FILE" ] || { echo "No Infisical robot login at $ID_FILE." >&2; exit 1; }
# The CLI reads these two variables for universal-auth login, so the secret
# never appears on a command line.
set -a; . "$ID_FILE"; set +a
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$INFISICAL_CLIENT_ID"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$INFISICAL_CLIENT_SECRET"
unset INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET
TOKEN="$(infisical login --method=universal-auth --domain="$DOMAIN" --silent --plain 2>/dev/null || true)"
unset INFISICAL_UNIVERSAL_AUTH_CLIENT_ID INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET
[ -n "$TOKEN" ] || { echo 'Infisical robot login failed.' >&2; exit 1; }
export INFISICAL_TOKEN="$TOKEN"
unset TOKEN

cleanup() {
  # The decoded keystore must not stay on disk.
  rm -rf "$ROOT/build/signing"
  # Stop the Gradle daemon so builds don't pile up background Java processes.
  [ -x "$ROOT/android/gradlew" ] && "$ROOT/android/gradlew" -p "$ROOT/android" --stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo 'building with keys from Infisical ...'
infisical run --projectId "$PROJECT" --env prod --domain "$DOMAIN" --silent -- \
  flutter build apk --release --split-per-abi \
    --build-name="$VERSION" --build-number="$BUILD_NUMBER" \
    --dart-define=NOTERR_APP_VERSION="$VERSION"
unset INFISICAL_TOKEN

APK="$ROOT/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
[ -f "$APK" ] || { echo "APK not found: $APK" >&2; exit 1; }

SIGNER="$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)"
CERT="$("$SIGNER" verify --print-certs "$APK" | sed -n 's/.*Signer #1 certificate SHA-256 digest:[[:space:]]*//p' | tr -d '[:space:]')"
if [ "$CERT" != "$EXPECTED_CERT" ]; then
  echo "APK is NOT signed with the release key (got '$CERT'). Not publishing." >&2
  exit 1
fi
echo 'signature: OK (release key)'

OUT="$ROOT/noterr-android-arm64-v$VERSION.apk"
cp "$APK" "$OUT"
echo "apk     : $OUT"
