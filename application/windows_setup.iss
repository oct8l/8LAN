#define PortableDir "..\\artifacts\\windows\\runtime\\portable"
#define AppName "8LAN"
#define ExePath "{#PortableDir}\\8LAN.Core.exe"
#define Version GetStringFileInfo(ExePath, 'ProductVersion')
#define VersionTag GetStringFileInfo(ExePath, 'VersionTag')
#define BuildTime GetStringFileInfo(ExePath, 'BuildTime')

[Setup]
AppName={#AppName}
AppVersion={#Version} {#VersionTag} - {#BuildTime}
SetupIconFile=.\Common\ressources\icon.ico
DefaultDirName={pf}/{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}/8LAN.Core.exe
Compression=lzma2
SolidCompression=yes
OutputDir=Installations
OutputBaseFilename={#AppName}-{#Version}{#VersionTag}-{#BuildTime}-Setup

[Files]
; Use the CI-produced portable runtime as source-of-truth.
; This avoids drift in hardcoded DLL/plugin lists as dependencies evolve.
Source: "{#PortableDir}\*"; DestDir: "{app}"; Flags: comparetimestamp recursesubdirs createallsubdirs

; Optional utilities.
Source: "Tools/LogViewer/output/release/LogViewer.exe"; DestDir: "{app}"; Flags: comparetimestamp skipifsourcedoesntexist
Source: "Tools/PasswordHasher/output/release/PasswordHasher.exe"; DestDir: "{app}"; Flags: comparetimestamp skipifsourcedoesntexist

[Icons]
Name: "{group}\8LAN"; Filename: "{app}\8LAN.GUI.exe"; WorkingDir: "{app}"
Name: "{group}\Password Hasher"; Filename: "{app}\PasswordHasher.exe"; WorkingDir: "{app}"; Check: FileExists(ExpandConstant('{app}\PasswordHasher.exe'))

[Languages]
; Name has to be coded as ISO-639 (two letters).
Name: "en"; MessagesFile: "compiler:Default.isl,translations\8lan.en.isl"
Name: "fr"; MessagesFile: "compiler:Languages\French.isl,translations\8lan.fr.isl"

[Tasks]
Name: "Firewall"; Description: {cm:firewallException}; MinVersion: 0,5.01.2600sp2;
Name: "ResetSettings"; Description: {cm:resetSettings}

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""8LAN Core In"" dir=in action=allow program=""{app}\8LAN.Core.exe"" profile=private enable=yes"; Flags: runhidden; MinVersion: 0,5.01.2600sp2; Tasks: Firewall
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""8LAN Core Out"" dir=out action=allow program=""{app}\8LAN.Core.exe"" profile=private enable=yes"; Flags: runhidden; MinVersion: 0,5.01.2600sp2; Tasks: Firewall
Filename: "{app}\8LAN.Core.exe"; Parameters: "--reset-settings"; Flags: RunHidden; Description: "Reset settings"; Tasks: ResetSettings
Filename: "{app}\8LAN.Core.exe"; Parameters: "-i --lang {language}"; Flags: RunHidden; Description: "Install the 8LAN service and define the language"
Filename: "{app}\8LAN.GUI.exe"; Parameters: "--lang {language}"; Flags: RunHidden; Description: "Define the language for the GUI"
Filename: "{app}\8LAN.GUI.exe"; Flags: nowait postinstall runasoriginaluser; Description: "{cm:launch8LAN}"

[UninstallRun]
Filename: "{app}\8LAN.Core.exe"; Parameters: "-u";
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""8LAN Core In"""; Flags: runhidden; MinVersion: 0,5.01.2600sp2; Tasks: Firewall;
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""8LAN Core Out"""; Flags: runhidden; MinVersion: 0,5.01.2600sp2; Tasks: Firewall;

[Code]
// Will stop the Core service.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: integer;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop "8LAN Core"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  NeedsRestart := False;
  Result := '';
end;
