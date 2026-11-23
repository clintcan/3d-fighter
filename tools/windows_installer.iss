; Inno Setup script for the 3D Fighter Windows installer (Inno Setup 6).
; Built by tools/build_release.py windows, which passes the version and paths:
;   ISCC /DAppVersion=0.10.3 /DGameExe=build\windows\3DFighter.exe /DOutputDir=dist tools\windows_installer.iss
; Installs for the current user by default (no admin prompt); the dialog offers all users.
; Saves, settings and replays live in %APPDATA%\Godot\app_userdata\3DFighter and survive an uninstall.

#ifndef AppVersion
  #error Pass /DAppVersion=x.y.z
#endif
#ifndef GameExe
  #define GameExe "..\build\windows\3DFighter.exe"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

[Setup]
; Never change AppId: upgrades and the uninstaller find the game by it.
AppId={{17B91082-D11E-41B8-9C20-CD6109E76E59}
AppName=3D Fighter
AppVersion={#AppVersion}
AppVerName=3D Fighter {#AppVersion}
AppPublisher=Clint Christopher Canada
AppPublisherURL=https://github.com/clintcan/3d-fighter
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName=3D Fighter
DefaultDirName={autopf}\3D Fighter
DefaultGroupName=3D Fighter
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
SetupIconFile=..\assets\ui\icon.ico
UninstallDisplayIcon={app}\3DFighter.exe
UninstallDisplayName=3D Fighter
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
CloseApplications=yes
OutputDir={#OutputDir}
OutputBaseFilename=3DFighter-v{#AppVersion}-windows-setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#GameExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\manual.html"; DestDir: "{app}"; DestName: "Manual.html"; Flags: ignoreversion

[Icons]
Name: "{group}\3D Fighter"; Filename: "{app}\3DFighter.exe"
Name: "{group}\3D Fighter Manual"; Filename: "{app}\Manual.html"
Name: "{group}\{cm:UninstallProgram,3D Fighter}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\3D Fighter"; Filename: "{app}\3DFighter.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\3DFighter.exe"; Description: "{cm:LaunchProgram,3D Fighter}"; Flags: nowait postinstall skipifsilent
