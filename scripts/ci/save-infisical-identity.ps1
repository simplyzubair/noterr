<#
.SYNOPSIS
    Save the Infisical robot (machine identity) that builds the Android app.

.DESCRIPTION
    Asks for the robot's Client ID and Client Secret (the secret is hidden
    while you paste it), tests that they can log in to Infisical, and saves
    them to %LOCALAPPDATA%\noterr-ci\infisical-identity.xml. The secret is
    encrypted by Windows for your user account, so only you on this PC can
    read it. Nothing is printed.

    Create the robot first in Infisical: Organization > Access Control >
    Identities > Create (Universal Auth, organization role "No Access"), then
    add it to project "noterr" with role "Viewer".
#>
$ErrorActionPreference = 'Stop'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')
$Domain  = 'https://contabo-sin-01.tail594efe.ts.net:8443/api'
$Project = 'dc732f83-ec69-465d-9216-2d911d2db9d4'

$clientId = (Read-Host 'Client ID').Trim()
$secure   = Read-Host 'Client Secret (hidden)' -AsSecureString
if (-not $clientId -or $secure.Length -eq 0) { throw 'Both values are needed. Nothing saved.' }

$plain = [Net.NetworkCredential]::new('', $secure).Password
$token = (& infisical login --method=universal-auth --client-id=$clientId `
    --client-secret=$plain --domain=$Domain --silent --plain 2>$null | Out-String).Trim()
$plain = $null
if (-not $token) { throw 'Login test FAILED. Check the Client ID and Secret. Nothing saved.' }

# The robot must be able to read the signing keys, or builds will fail later.
$alias = (& infisical secrets get ANDROID_KEY_ALIAS --plain --silent --token=$token `
    --projectId $Project --env prod --domain $Domain 2>$null | Out-String).Trim()
if (-not $alias) {
    throw 'Login works, but the robot cannot read project "noterr". Add it to the project as Viewer. Nothing saved.'
}

$dir = Join-Path $env:LOCALAPPDATA 'noterr-ci'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[pscustomobject]@{ ClientId = $clientId; ClientSecret = $secure } |
    Export-Clixml (Join-Path $dir 'infisical-identity.xml')
Write-Host 'SAVED. Login test OK, project access OK.'
