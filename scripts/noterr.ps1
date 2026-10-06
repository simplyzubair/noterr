<#
.SYNOPSIS
    Install, update and inspect Noterr on Windows without touching the GUI.

.DESCRIPTION
    Pulls the latest published release from GitHub and runs the Inno Setup
    installer silently, so a new version can be rolled out from a terminal or a
    scheduled task. Also exposes the vault doctor, which reports why a vault
    refuses a passphrase.

.PARAMETER Command
    install   Install or upgrade to the newest published release.
    version   Show the installed version and the newest published one.
    doctor    Run the vault diagnostic against the installed app.
    uninstall Remove the installed copy.

.PARAMETER Version
    Install an exact tag, for example v0.3.4, instead of the newest release.

.EXAMPLE
    .\scripts\noterr.ps1 install

.EXAMPLE
    .\scripts\noterr.ps1 install -Version v0.3.4
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'version', 'doctor', 'uninstall')]
    [string]$Command = 'version',

    [string]$Version
)

$ErrorActionPreference = 'Stop'
$Repo = 'simplyzubair/noterr'
$InstallDir = Join-Path $env:ProgramFiles 'Noterr'
$ExePath = Join-Path $InstallDir 'noterr.exe'

function Get-InstalledVersion {
    if (-not (Test-Path $ExePath)) { return $null }
    return (Get-Item $ExePath).VersionInfo.FileVersion
}

function Get-Release {
    param([string]$Tag)
    $uri = if ($Tag) {
        "https://api.github.com/repos/$Repo/releases/tags/$Tag"
    } else {
        "https://api.github.com/repos/$Repo/releases/latest"
    }
    try {
        return Invoke-RestMethod -Uri $uri -Headers @{ Accept = 'application/vnd.github+json' }
    } catch {
        throw "Could not read release info from GitHub: $($_.Exception.Message)"
    }
}

function Invoke-Install {
    param([string]$Tag)

    $release = Get-Release -Tag $Tag
    $asset = $release.assets | Where-Object { $_.name -like 'NoterrSetup-*.exe' } | Select-Object -First 1
    if (-not $asset) {
        throw "Release $($release.tag_name) has no NoterrSetup-*.exe asset. Nothing to install."
    }

    $installed = Get-InstalledVersion
    Write-Host "installed: $(if ($installed) { $installed } else { 'none' })"
    Write-Host "release  : $($release.tag_name)"

    $target = Join-Path $env:TEMP $asset.name
    Write-Host "downloading $($asset.name) ..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $target

    $size = (Get-Item $target).Length
    if ($size -lt 1MB) {
        throw "Downloaded file is only $size bytes; that is not the installer."
    }

    Write-Host 'installing silently ...'
    $proc = Start-Process -FilePath $target `
        -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/FORCECLOSEAPPLICATIONS' `
        -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Installer exited with code $($proc.ExitCode)."
    }

    Remove-Item $target -Force -ErrorAction SilentlyContinue
    Write-Host "done. now installed: $(Get-InstalledVersion)"
}

function Invoke-Version {
    $installed = Get-InstalledVersion
    Write-Host "installed: $(if ($installed) { $installed } else { 'not installed' })"
    try {
        $release = Get-Release
        Write-Host "latest   : $($release.tag_name)"
    } catch {
        Write-Host 'latest   : unavailable (no published release, or no network)'
    }
}

function Invoke-Doctor {
    if (-not (Test-Path $ExePath)) { throw "Noterr is not installed at $InstallDir." }
    & $ExePath --vault-doctor
}

function Invoke-Uninstall {
    $uninstaller = Join-Path $InstallDir 'unins000.exe'
    if (-not (Test-Path $uninstaller)) { throw "No uninstaller found at $uninstaller." }
    $proc = Start-Process -FilePath $uninstaller `
        -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "Uninstaller exited with code $($proc.ExitCode)." }
    Write-Host 'uninstalled. Notes in %APPDATA%\com.example\noterr were left alone.'
}

switch ($Command) {
    'install'   { Invoke-Install -Tag $Version }
    'version'   { Invoke-Version }
    'doctor'    { Invoke-Doctor }
    'uninstall' { Invoke-Uninstall }
}
