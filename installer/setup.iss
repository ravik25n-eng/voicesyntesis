[Setup]
AppName=VoiceModulation
AppVersion=1.0
AppPublisher=VoiceModulation
DefaultDirName={localappdata}\VoiceModulation
DefaultGroupName=VoiceModulation
OutputDir=dist
OutputBaseFilename=VoiceModulation-Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\launch.bat
WizardStyle=modern
SetupIconFile=

[Components]
Name: "app";    Description: "VoiceModulation App (required)"; Types: full compact custom; Flags: fixed
Name: "models"; Description: "Download AI Models — Whisper + F5-TTS (~4.5 GB, fast internet recommended)"; Types: full

[Files]
; App source
Source: "..\backend\*";       DestDir: "{app}\backend";       Flags: recursesubdirs ignoreversion; Components: app
Source: "..\frontend\dist\*"; DestDir: "{app}\frontend\dist"; Flags: recursesubdirs ignoreversion; Components: app

; Installer helper scripts
Source: "install_deps.ps1"; DestDir: "{app}"; Flags: ignoreversion; Components: app
Source: "start_app.ps1";    DestDir: "{app}"; Flags: ignoreversion; Components: app
Source: "launch.bat";       DestDir: "{app}"; Flags: ignoreversion; Components: app

[Icons]
Name: "{userdesktop}\VoiceModulation";        Filename: "{app}\launch.bat"; WorkingDir: "{app}"; Comment: "Start VoiceModulation"
Name: "{userprograms}\VoiceModulation\Launch"; Filename: "{app}\launch.bat"; WorkingDir: "{app}"
Name: "{userprograms}\VoiceModulation\Uninstall VoiceModulation"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\install_deps.ps1"" -InstallDir ""{app}"" {code:GetModelsFlag}"; \
  StatusMsg: "Installing dependencies — this takes several minutes, please wait..."; \
  Flags: runhidden waituntilterminated; \
  Components: app

[UninstallDelete]
Type: filesandordirs; Name: "{app}\.venv"
Type: filesandordirs; Name: "{app}\backend\projects"

[Code]
function GetModelsFlag(Param: String): String;
begin
  if IsComponentSelected('models') then
    Result := '-DownloadModels'
  else
    Result := '';
end;
