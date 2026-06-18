$ErrorActionPreference = "Stop"

$repo = "simplyzubair/noterr"
$configPath = Join-Path $PSScriptRoot "sync_config.bat"

$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if (!$ghCommand) {
  $knownGhPaths = @(
    "C:\Program Files\GitHub CLI\gh.exe",
    "C:\Program Files (x86)\GitHub CLI\gh.exe",
    "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe"
  )
  $ghPath = $knownGhPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
} else {
  $ghPath = $ghCommand.Source
}

if (!$ghPath) {
  Write-Host "GitHub CLI is not installed." -ForegroundColor Yellow
  Write-Host "Install it from https://cli.github.com/, then run this script again."
  exit 1
}

if (!(Test-Path $configPath)) {
  Write-Host "sync_config.bat was not found next to this script." -ForegroundColor Yellow
  Write-Host "Run Configure-Sync.bat first."
  exit 1
}

& $ghPath auth status 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) {
  Write-Host "GitHub CLI is not signed in." -ForegroundColor Yellow
  Write-Host "Run: `"$ghPath`" auth login"
  exit 1
}

$config = Get-Content $configPath
$url = ($config | Where-Object { $_ -like 'set "NOTERR_SYNC_URL=*' }) -replace '^set "NOTERR_SYNC_URL=', '' -replace '"$', ''

if ([string]::IsNullOrWhiteSpace($url)) {
  Write-Host "NOTERR_SYNC_URL was not found in sync_config.bat." -ForegroundColor Yellow
  exit 1
}

& $ghPath secret set NOTERR_SYNC_URL --repo $repo --body $url

Write-Host "GitHub Actions secrets saved for $repo." -ForegroundColor Green
