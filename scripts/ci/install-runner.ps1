<#
.SYNOPSIS
    Install the GitHub Actions runner that builds the Noterr Android app on
    this PC.

.DESCRIPTION
    GitHub can't reach Infisical (it is Tailscale only), so the Android build
    runs here. This script:
      1. downloads the official runner into D:\Runners\noterr,
      2. registers it with the noterr repo under the label "noterr-android",
      3. adds a Windows scheduled task that starts it when you log in, hidden,
      4. makes GitHub ask for approval before running workflows from any
         outside contributor, so a stranger's pull request can't run code on
         this PC.

    Needs `gh auth login` first. Safe to run again: it replaces the old
    registration.
#>
$ErrorActionPreference = 'Stop'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

$Repo     = 'simplyzubair/noterr'
$Dir      = 'D:\Runners\noterr'
$TaskName = 'Noterr GitHub runner'

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'Run "gh auth login" first.' }

# 1. Download
if (-not (Test-Path (Join-Path $Dir 'config.cmd'))) {
    $rel = Invoke-RestMethod 'https://api.github.com/repos/actions/runner/releases/latest'
    $asset = $rel.assets | Where-Object { $_.name -match '^actions-runner-win-x64-[\d.]+\.zip$' } |
             Select-Object -First 1
    if (-not $asset) { throw 'Could not find the Windows runner download.' }
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $zip = Join-Path $env:TEMP $asset.name
    Write-Host "downloading $($asset.name) ..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip
    Expand-Archive $zip -DestinationPath $Dir -Force
    Remove-Item $zip -Force
}

# 2. Register (a short-lived token from GitHub, never printed)
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Stop-ScheduledTask
Get-Process Runner.Listener -ErrorAction SilentlyContinue | Stop-Process -Force
$token = (& gh api -X POST "repos/$Repo/actions/runners/registration-token" --jq .token).Trim()
if (-not $token) { throw 'Could not get a runner registration token.' }
Push-Location $Dir
try {
    & .\config.cmd --unattended --replace --url "https://github.com/$Repo" --token $token `
        --name "noterr-$env:COMPUTERNAME" --labels noterr-android --work _work
    if ($LASTEXITCODE -ne 0) { throw "Runner registration failed (exit $LASTEXITCODE)." }
} finally { Pop-Location; $token = $null }

# 3. Start at logon, as you, so it can use Flutter, the Android SDK and the
#    saved Infisical robot. No password is stored.
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"Set-Location '$Dir'; & .\run.cmd`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Description 'Builds the Noterr Android app for GitHub Actions.' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

# 4. Outside contributors' workflows wait for approval.
& gh api -X PUT "repos/$Repo/actions/permissions/fork-pr-contributor-approval" `
    -f approval_policy=all_external_contributors | Out-Null

Start-Sleep -Seconds 10
$state = (& gh api "repos/$Repo/actions/runners" --jq '.runners[] | "\(.name) \(.status)"')
Write-Host "runner: $state"
