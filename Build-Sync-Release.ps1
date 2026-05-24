$ErrorActionPreference = "Stop"

$Flutter = "C:\tmp\flutter\bin\flutter.bat"
$Project = "C:\tmp\NoterrBuild"
$Config = "C:\Users\zubai\Documents\Noterr\sync_config.bat"
$InstallDir = "$env:LOCALAPPDATA\Programs\Noterr"

if (!(Test-Path $Config)) {
  throw "Sync config was not found. Run Configure-Sync.bat first."
}

$configText = Get-Content $Config
$SupabaseUrl = (($configText | Where-Object { $_ -match '^set\s+"?SUPABASE_URL=' } | Select-Object -First 1) -replace '^set\s+"?SUPABASE_URL=', '') -replace '"$', ''
$SupabaseAnonKey = (($configText | Where-Object { $_ -match '^set\s+"?SUPABASE_ANON_KEY=' } | Select-Object -First 1) -replace '^set\s+"?SUPABASE_ANON_KEY=', '') -replace '"$', ''

if ([string]::IsNullOrWhiteSpace($SupabaseUrl) -or [string]::IsNullOrWhiteSpace($SupabaseAnonKey)) {
  throw "Sync config is incomplete. Run Configure-Sync.bat first."
}

Push-Location $Project
try {
  & $Flutter analyze
  & $Flutter test test\widget_test.dart test\sticky_window_payload_test.dart
  & $Flutter build windows --release --dart-define="SUPABASE_URL=$SupabaseUrl" --dart-define="SUPABASE_ANON_KEY=$SupabaseAnonKey"
  & $Flutter build apk --release --target-platform android-arm64 --dart-define="SUPABASE_URL=$SupabaseUrl" --dart-define="SUPABASE_ANON_KEY=$SupabaseAnonKey"

  Get-Process noterr -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  robocopy "$Project\build\windows\x64\runner\Release" $InstallDir /MIR /NFL /NDL /NJH /NJS /NP
  if ($LASTEXITCODE -ge 8) {
    throw "Windows install copy failed."
  }

  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut("$env:USERPROFILE\Desktop\Noterr.lnk")
  $shortcut.TargetPath = Join-Path $InstallDir "noterr.exe"
  $shortcut.WorkingDirectory = $InstallDir
  $shortcut.IconLocation = (Join-Path $InstallDir "noterr.exe") + ",0"
  $shortcut.Save()

  reg add HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v Noterr /t REG_SZ /d "`"$(Join-Path $InstallDir "noterr.exe")`"" /f | Out-Null

  Write-Host "Sync-enabled Windows app:" (Join-Path $InstallDir "noterr.exe")
  Write-Host "Sync-enabled APK:" "$Project\build\app\outputs\flutter-apk\app-release.apk"
} finally {
  Pop-Location
}
