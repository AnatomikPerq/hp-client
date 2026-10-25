; Fastforge renders this template; EXE and ZIP share one Flutter build.
; HYPER CLIENT installs per machine (Program Files): the TUN Core is started
; elevated from the install folder, which therefore must not be writable by
; unprivileged processes. HKA is HKLM in this mode. [Run] postinstall entries
; run as the original, non-elevated user by default.
[Setup]
AppId={{APP_ID}}
AppName={{DISPLAY_NAME}}
AppVersion={{APP_VERSION}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL=https://github.com/AnatomikPerq/hp-client/issues
AppUpdatesURL=https://github.com/AnatomikPerq/hp-client/releases
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma2
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
UninstallDisplayIcon={app}\{{EXECUTABLE_NAME}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCHITECTURES_ALLOWED}}
ArchitecturesInstallIn64BitMode={{ARCHITECTURES_INSTALL_IN_64BIT_MODE}}
MinVersion=10.0.19042
CloseApplications=yes
RestartApplications=no
; Created by windows/runner/main.cpp. Restart Manager cannot close the App
; (closing its window only hides it to the tray) and never reaches another
; session, so both setup and uninstall left files under a running App; this
; asks the user to quit it first, which also disconnects cleanly.
AppMutex=HyperClientAppRunning,Global\HyperClientAppRunning

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}

[Files]
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; WorkingDir: "{app}"
Name: "{autodesktop}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Classes\hyperclient"; ValueType: string; ValueName: ""; ValueData: "URL:HYPER CLIENT Protocol"
Root: HKA; Subkey: "Software\Classes\hyperclient"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\hyperclient\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{{EXECUTABLE_NAME}}"",0"
Root: HKA; Subkey: "Software\Classes\hyperclient\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{{EXECUTABLE_NAME}}"" ""%1"""

[Run]
Filename: "{app}\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; A Core that crashed may have left the kill switch blocking the internet;
; without the App nothing would lift it. The uninstaller runs elevated.
Filename: "{app}\HyperClientCore.exe"; Parameters: "unblock"; Flags: runhidden waituntilterminated; RunOnceId: "LiftKillSwitch"

[Code]
{ Update mode (/HCUPDATE=1), started by the App's update button. Once UAC
  was accepted this creates HyperClientUpdating; the App waits for it, then
  stops the VPN (keeping the kill switch) and exits. InitializeSetup runs
  before the AppMutex check, so Setup waits here instead of refusing. The App
  is started again as the original user whether or not the update went in. }
var
  AppClosedForUpdate: Boolean;

function CreateMutexW(Attributes: Cardinal; InitialOwner: Boolean;
  Name: String): THandle;
  external 'CreateMutexW@kernel32.dll stdcall';

function IsAppUpdate: Boolean;
begin
  Result := ExpandConstant('{param:HCUPDATE|0}') = '1';
end;

function InitializeSetup: Boolean;
var
  Waited: Integer;
begin
  Result := True;
  if not IsAppUpdate then
    Exit;
  { Closed by Windows when Setup exits. }
  CreateMutexW(0, False, 'HyperClientUpdating');
  Waited := 0;
  while CheckForMutexes('HyperClientAppRunning,Global\HyperClientAppRunning') and
        (Waited < 120000) do
  begin
    Sleep(250);
    Waited := Waited + 250;
  end;
  AppClosedForUpdate :=
    not CheckForMutexes('HyperClientAppRunning,Global\HyperClientAppRunning');
  { A line that starts with a bracket would open a new section. }
  Log(Format('Update mode: waited %d ms for the App to exit, closed: %d', [
    Waited, Ord(AppClosedForUpdate)]));
end;

procedure DeinitializeSetup;
var
  ResultCode: Integer;
begin
  if not AppClosedForUpdate then
    Exit;
  try
    if not ExecAsOriginalUser(ExpandConstant('{app}\{{EXECUTABLE_NAME}}'), '',
        '', SW_SHOWNORMAL, ewNoWait, ResultCode) then
      Log('Unable to start HYPER CLIENT after the update: ' +
        SysErrorMessage(ResultCode));
  except
    Log('Unable to start HYPER CLIENT after the update.');
  end;
end;

function StartupShortcutTargetsCurrentInstall(const ShortcutPath,
  ExpectedTarget: String): Boolean;
var
  Shell, Shortcut: Variant;
  TargetPath: String;
begin
  Result := False;
  if not FileExists(ShortcutPath) then
    Exit;
  try
    Shell := CreateOleObject('WScript.Shell');
    Shortcut := Shell.CreateShortcut(ShortcutPath);
    TargetPath := Shortcut.TargetPath;
    Result := (TargetPath <> '') and PathSame(TargetPath, ExpectedTarget);
  except
    Log('Unable to inspect the HYPER CLIENT startup shortcut.');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ExpectedTarget, ShortcutPath, CurrentCommand: String;
begin
  if CurUninstallStep <> usUninstall then
    Exit;
  ExpectedTarget := ExpandConstant('{app}\{{EXECUTABLE_NAME}}');
  ShortcutPath := ExpandConstant('{userstartup}\{{DISPLAY_NAME}}.lnk');
  if StartupShortcutTargetsCurrentInstall(ShortcutPath, ExpectedTarget) and
     not DeleteFile(ShortcutPath) then
    Log('Unable to remove the HYPER CLIENT startup shortcut.');
  { Never remove another installation's protocol registration. }
  if RegQueryStringValue(HKA, 'Software\Classes\hyperclient\shell\open\command',
      '', CurrentCommand) and
     (CompareText(CurrentCommand, '"' + ExpectedTarget + '" "%1"') = 0) then
    RegDeleteKeyIncludingSubkeys(HKA, 'Software\Classes\hyperclient');
end;
