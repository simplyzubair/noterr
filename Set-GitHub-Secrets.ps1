$ErrorActionPreference = "Stop"

$repo = "simplyzubair/noterr"
$configPath = Join-Path $PSScriptRoot "sync_config.bat"

if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-Host "GitHub CLI is not installed." -ForegroundColor Yellow
  Write-Host "Install it from https://cli.github.com/, then run this script again."
  exit 1
}

if (!(Test-Path $configPath)) {
  Write-Host "sync_config.bat was not found next to this script." -ForegroundColor Yellow
  Write-Host "Run Configure-Sync.bat first."
  exit 1
}

$auth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "GitHub CLI is not signed in." -ForegroundColor Yellow
  Write-Host "Run: gh auth login"
  exit 1
}

$config = Get-Content $configPath
$url = ($config | Where-Object { $_ -like 'set "SUPABASE_URL=*' }) -replace '^set "SUPABASE_URL=', '' -replace '"$', ''
$key = ($config | Where-Object { $_ -like 'set "SUPABASE_ANON_KEY=*' }) -replace '^set "SUPABASE_ANON_KEY=', '' -replace '"$', ''

if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($key)) {
  Write-Host "Supabase URL/key were not found in sync_config.bat." -ForegroundColor Yellow
  exit 1
}

gh secret set NOTERR_SUPABASE_URL --repo $repo --body $url
gh secret set NOTERR_SUPABASE_ANON_KEY --repo $repo --body $key

Write-Host "GitHub Actions secrets saved for $repo." -ForegroundColor Green
