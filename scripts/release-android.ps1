<#
.SYNOPSIS
    Build, sign and publish the Noterr Android APK from this PC.

.DESCRIPTION
    Signing keys come from Infisical (project noterr, env prod) through
    `infisical run`, so they never touch GitHub or the repo. The script builds
    the split release APKs, deletes the decoded keystore, checks that the APK
    carries the real release certificate, and uploads the arm64 APK to the
    GitHub release for the version in pubspec.yaml.

    Needs: Tailscale on, `infisical login` done once, `gh auth login` done once
    (only for -Upload).

.PARAMETER Upload
    Upload the APK to the GitHub release vX.Y.Z. Without it the script only
    builds and verifies.

.EXAMPLE
    .\scripts\release-android.ps1 -Upload
#>
[CmdletBinding()]
param([switch]$Upload)

$ErrorActionPreference = 'Stop'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

$Repo       = 'simplyzubair/noterr'
$Domain     = 'https://contabo-sin-01.tail594efe.ts.net:8443/api'
$Project    = 'dc732f83-ec69-465d-9216-2d911d2db9d4'
# SHA-256 of the release certificate (public, not a secret). Any other value
# means the APK could not be installed over existing installs.
$ExpectedCert = 'a4baaed4a8c8427e0e2231fe72fca20db986e13082aeb39c6ae4d2b68e84dab1'

$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

function Find-Flutter {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in 'C:\tmp\flutter\bin\flutter.bat', "$env:USERPROFILE\flutter\bin\flutter.bat") {
        if (Test-Path $p) { return $p }
    }
    throw 'Flutter not found.'
}

function Find-ApkSigner {
    $tools = Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools'
    $s = Get-ChildItem "$tools\*\apksigner.bat" -ErrorAction SilentlyContinue |
         Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $s) { throw "apksigner not found under $tools." }
    if (-not $env:JAVA_HOME) {
        $jbr = 'C:\Program Files\Android\Android Studio\jbr'
        if (Test-Path $jbr) { $env:JAVA_HOME = $jbr; $env:Path = "$jbr\bin;$env:Path" }
    }
    return $s.FullName
}

if (-not (Get-Command infisical -ErrorAction SilentlyContinue)) {
    throw 'Infisical CLI not installed. Run: winget install infisical.infisical'
}

$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -replace '\+.*', '').Trim()
$tag = "v$version"
Write-Host "version : $version"

$flutter = Find-Flutter
# Flutter points Gradle's root build dir at <repo>/build, so the decoded
# keystore lands in build\signing.
$signingDir = Join-Path $Root 'build\signing'

try {
    Write-Host 'building with keys from Infisical ...'
    & infisical run --projectId $Project --env prod --domain $Domain --silent `
        --command "`"$flutter`" build apk --release --split-per-abi --dart-define=NOTERR_APP_VERSION=$version"
    if ($LASTEXITCODE -ne 0) { throw "Build failed (exit $LASTEXITCODE)." }
} finally {
    # The decoded keystore must not stay on disk.
    if (Test-Path $signingDir) { Remove-Item $signingDir -Recurse -Force }
}

$apk = Join-Path $Root 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
if (-not (Test-Path $apk)) { throw "APK not found: $apk" }

$signer = Find-ApkSigner
$certLine = & $signer verify --print-certs $apk 2>&1 | Select-String 'Signer #1 certificate SHA-256 digest'
$cert = ($certLine -replace '.*digest:\s*', '').ToString().Trim()
if ($cert -ne $ExpectedCert) {
    throw "APK is NOT signed with the release key (got '$cert'). Not publishing."
}
Write-Host 'signature: OK (release key)'

$out = Join-Path $Root "noterr-android-arm64-v$version.apk"
Copy-Item $apk $out -Force
Write-Host "apk     : $out"

if ($Upload) {
    & gh release view $tag --repo $Repo *> $null
    if ($LASTEXITCODE -ne 0) { throw "GitHub release $tag does not exist yet. Push the tag and let CI publish it first." }
    & gh release upload $tag $out --repo $Repo --clobber
    if ($LASTEXITCODE -ne 0) { throw "Upload failed (exit $LASTEXITCODE)." }
    Write-Host "uploaded to $tag"
}
