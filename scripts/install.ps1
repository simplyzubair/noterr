# Install or update Noterr on any Windows PC with one line in PowerShell:
#
#   irm https://raw.githubusercontent.com/simplyzubair/noterr/master/scripts/install.ps1 | iex
#
# Downloads the newest Windows installer from GitHub Releases and runs it
# silently. Windows asks once to allow changes (it installs to Program
# Files). Running it again updates to the newest version; notes are kept.
& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $rel = Invoke-RestMethod 'https://api.github.com/repos/simplyzubair/noterr/releases/latest'
    $asset = $rel.assets | Where-Object { $_.name -like 'NoterrSetup-*.exe' } | Select-Object -First 1
    if (-not $asset) { throw "Release $($rel.tag_name) has no Windows installer." }

    $file = Join-Path $env:TEMP $asset.name
    Write-Host "Downloading Noterr $($rel.tag_name) ..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $file

    Write-Host 'Installing (Windows will ask to allow changes) ...'
    $p = Start-Process $file -Wait -PassThru `
        -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/FORCECLOSEAPPLICATIONS'
    Remove-Item $file -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) { throw "Installer exited with code $($p.ExitCode)." }

    $exe = Join-Path $env:ProgramFiles 'Noterr\noterr.exe'
    Write-Host "Noterr $((Get-Item $exe).VersionInfo.FileVersion) installed."
    Start-Process $exe
}
