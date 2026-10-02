$ErrorActionPreference = "Stop"

$Flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) { "flutter" } else { "C:\tmp\flutter\bin\flutter.bat" }
$Project = $PSScriptRoot          # always the directory this script lives in
$Config = Join-Path $PSScriptRoot "sync_config.bat"
$InstallDir = "$env:LOCALAPPDATA\Programs\Noterr"

if (!(Test-Path $Config)) {
  throw "Sync config was not found. Run Configure-Sync.bat first."
}

$configText = Get-Content $Config
$SyncUrl = (($configText | Where-Object { $_ -match '^set\s+"?NOTERR_SYNC_URL=' } | Select-Object -First 1) -replace '^set\s+"?NOTERR_SYNC_URL=', '') -replace '"$', ''

if ([string]::IsNullOrWhiteSpace($SyncUrl)) {
  throw "Sync config is incomplete. Run Configure-Sync.bat first."
}

if ($SyncUrl -notmatch '^https://') {
  throw "Sync config must be an https Worker URL. Run Configure-Sync.bat again."
}

$ParsedSyncUrl = [Uri]$SyncUrl
if (
  $ParsedSyncUrl.Host -eq "welcome.developers.workers.dev" -or
  $ParsedSyncUrl.AbsolutePath -match "wrangler-oauth-consent-granted"
) {
  throw "Sync config points to the Cloudflare login/welcome page, not the Noterr sync Worker. Deploy the Worker, copy its workers.dev URL, then run Configure-Sync.bat again."
}

# Read version from pubspec.yaml for informational output
$pubspecVersion = (Get-Content (Join-Path $Project "pubspec.yaml") | Where-Object { $_ -match '^version:' } | Select-Object -First 1) -replace 'version:\s*', '' -replace '\+.*', ''
Write-Host "Building Noterr $pubspecVersion with sync URL: $SyncUrl" -ForegroundColor Cyan

Push-Location $Project
try {
  & $Flutter analyze
  & $Flutter test
  & $Flutter build windows --release --dart-define="NOTERR_SYNC_URL=$SyncUrl"
  & $Flutter build apk --release --target-platform android-arm64 --dart-define="NOTERR_SYNC_URL=$SyncUrl"

  Get-Process noterr -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  robocopy "$Project\build\windows\x64\runner\Release" $InstallDir /MIR /NFL /NDL /NJH /NJS /NP
  if ($LASTEXITCODE -ge 8) {
    throw "Windows install copy failed."
  }

  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut("$env:USERPROFILE\Desktop\Noterr.lnk")
  $shortcut.TargetPath = Join-Path $InstallDir "noterr.exe"
  $shortcut.Arguments = "--start-hidden"
  $shortcut.WorkingDirectory = $InstallDir
  $shortcut.IconLocation = (Join-Path $InstallDir "noterr.exe") + ",0"
  $shortcut.Save()

  reg add HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v Noterr /t REG_SZ /d "`"$(Join-Path $InstallDir "noterr.exe")`" --start-hidden" /f | Out-Null

  Write-Host ""
  Write-Host "✓ Noterr $pubspecVersion installed successfully!" -ForegroundColor Green
  Write-Host "  Windows: $(Join-Path $InstallDir "noterr.exe")"
  Write-Host "  Android APK: $Project\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
} finally {
  Pop-Location
}

