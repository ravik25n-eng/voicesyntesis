; ─────────────────────────────────────────────────────────────────────────────
; VoiceSyntesis — Inno Setup 6 installer script
;
; PRE-REQUISITE (developer machine only):
;   Build the React frontend BEFORE compiling this script:
;       cd frontend
;       npm install
;       npm run build
;   Or run:  installer\build_installer.ps1
;
; Produces: installer\dist\VoiceSyntesis-Setup.exe
; ─────────────────────────────────────────────────────────────────────────────

[Setup]
AppName=VoiceSyntesis
AppVersion=1.0
AppPublisher=VoiceSyntesis
AppComments=Local voice cloning — Record, transcribe, and synthesise speech in your own voice.
DefaultDirName={localappdata}\VoiceSyntesis
DefaultGroupName=VoiceSyntesis
OutputDir=dist
OutputBaseFilename=VoiceSyntesis-Setup
Compression=lzma2
SolidCompression=yes
; No admin rights needed — everything installs per-user
PrivilegesRequired=lowest
WizardStyle=modern
DisableProgramGroupPage=yes
; Require Windows 10 or later
MinVersion=10.0.17763
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Components]
Name: "app";    Description: "VoiceSyntesis application (required) — Installs Python 3.11, Node.js LTS, FFmpeg, Ollama, PyTorch, FastAPI, faster-whisper, F5-TTS"; Types: full compact custom; Flags: fixed
Name: "models"; Description: "Download AI models during install — Whisper large-v3 + F5-TTS (~4.5 GB). Recommended on a fast connection; otherwise models download on first use."; Types: full

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
; ── Backend Python source ───────────────────────────────────────────────────
Source: "..\backend\*"; DestDir: "{app}\backend"; Flags: recursesubdirs ignoreversion; Components: app

; ── Pre-built React frontend (run 'npm run build' in frontend/ first) ───────
Source: "..\frontend\dist\*"; DestDir: "{app}\frontend\dist"; Flags: recursesubdirs ignoreversion; Components: app

; ── Installer / launcher scripts ────────────────────────────────────────────
Source: "install_deps.ps1"; DestDir: "{app}"; Flags: ignoreversion; Components: app
Source: "start_app.ps1";    DestDir: "{app}"; Flags: ignoreversion; Components: app
Source: "launch.bat";       DestDir: "{app}"; Flags: ignoreversion; Components: app

[Icons]
; Desktop shortcut
Name: "{userdesktop}\VoiceSyntesis"; Filename: "{app}\launch.bat"; WorkingDir: "{app}"; Comment: "Start VoiceSyntesis"; Tasks: desktopicon
; Start-menu entries
Name: "{userprograms}\VoiceSyntesis\Launch VoiceSyntesis";    Filename: "{app}\launch.bat"; WorkingDir: "{app}"; Comment: "Start VoiceSyntesis"
Name: "{userprograms}\VoiceSyntesis\Uninstall VoiceSyntesis"; Filename: "{uninstallexe}"

[Run]
; Run the dependency installer after files are extracted.
; A visible PowerShell window opens so the user can see progress.
; Downloading PyTorch alone can take 5-15 min — StatusMsg sets expectations.
Filename: "powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -NoProfile -WindowStyle Normal -File ""{app}\install_deps.ps1"" -InstallDir ""{app}"" {code:GetModelsFlag}"; \
  StatusMsg: "Installing dependencies — a progress window will open. Steps: Python 3.11 → Node.js → FFmpeg → Ollama → PyTorch → Python packages → Ollama model. Do NOT close that window."; \
  Flags: waituntilterminated; \
  Components: app

; Offer to launch immediately after install
Filename: "{app}\launch.bat"; \
  Description: "Launch VoiceSyntesis now"; \
  Flags: postinstall nowait skipifsilent unchecked; \
  WorkingDir: "{app}"; \
  Components: app

[UninstallDelete]
; Remove generated files that Inno Setup's uninstaller won't know about
Type: filesandordirs; Name: "{app}\.venv"
Type: filesandordirs; Name: "{app}\tools"
Type: filesandordirs; Name: "{app}\backend\projects"

[Code]
{ Return -DownloadModels flag when the models component is selected }
function GetModelsFlag(Param: String): String;
begin
  if WizardIsComponentSelected('models') then
    Result := '-DownloadModels'
  else
    Result := '';
end;

