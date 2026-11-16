#define MyAppName "Noterr"
; CI passes the version with /DMyAppVersion=x.y.z; this is the fallback
; for local builds.
#ifndef MyAppVersion
  #define MyAppVersion "0.4.1"
#endif
#define MyAppPublisher "Noterr"
#define MyAppExeName "noterr.exe"

[Setup]
AppId={{31DF93AF-D0D6-4C27-8B43-F20B728A4E52}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=dist
OutputBaseFilename=NoterrSetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
; Noterr lives in the tray and its window refuses to close (it hides), so
; Windows' polite "please close" never ends it and Setup then failed with
; "DeleteFile failed; code 5" on the first file in use. Setup ends the app
; itself instead, in PrepareToInstall below.
CloseApplications=no

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--show-editor"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--show-editor"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Registry]
; The app adds itself to "start with Windows". Nothing is written here; this
; only takes that entry away again on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Noterr"; Flags: dontcreatekey uninsdeletevalue

[Run]
; By hand: a "Launch Noterr" tick box on the last page.
Filename: "{app}\{#MyAppExeName}"; Parameters: "--start-hidden"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
; Silent (the app updating itself, or scripts/install.ps1): start it again in
; the tray, as the user and not as administrator.
Filename: "{app}\{#MyAppExeName}"; Parameters: "--start-hidden"; Flags: nowait runasoriginaluser; Check: WizardSilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function NoterrRunning(): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'),
    '/C tasklist /FI "IMAGENAME eq {#MyAppExeName}" /NH | find /I "{#MyAppExeName}" >nul',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

{ Ends every running Noterr and waits until its files are free. Notes are
  saved on every change, so nothing is lost. }
function StopNoterr(): Boolean;
var
  ResultCode: Integer;
  Tries: Integer;
begin
  Tries := 0;
  while NoterrRunning() and (Tries < 20) do
  begin
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM {#MyAppExeName}',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(500);
    Tries := Tries + 1;
  end;
  Result := not NoterrRunning();
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not StopNoterr() then
    Result := 'Noterr is still running and could not be closed. ' +
      'Right-click the Noterr icon near the clock, choose "Exit Noterr", ' +
      'then run this setup again.';
end;

function InitializeUninstall(): Boolean;
begin
  StopNoterr();
  Result := True;
end;
