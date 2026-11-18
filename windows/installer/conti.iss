; Installationsprogramm für Conti (Inno Setup). Wird beim Build erzeugt:
;   iscc /DAppVersion=0.1.50 windows\installer\conti.iss
; Conti wird nur für den eigenen Benutzer installiert (keine Admin-Rechte nötig),
; in %LOCALAPPDATA%\Programs\Conti. Dort darf sich Conti selbst aktualisieren.
; Die Buchhaltungsdaten liegen woanders (%APPDATA%\Conti\Conti) und bleiben beim Deinstallieren.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{C70B9E38-0850-4BF5-90D6-027B5C7296AD}
AppName=Conti
AppVersion={#AppVersion}
AppVerName=Conti {#AppVersion}
AppPublisher=Conti
DefaultDirName={localappdata}\Programs\Conti
DisableDirPage=yes
DefaultGroupName=Conti
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=Conti-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Conti.exe
UninstallDisplayName=Conti
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage
CloseApplications=force
RestartApplications=no

[Languages]
; Sprache nach Windows: Deutsch (Schweizer Schreibweise) oder Englisch.
Name: "de"; MessagesFile: "German-CH.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Conti"; Filename: "{app}\Conti.exe"
Name: "{autodesktop}\Conti"; Filename: "{app}\Conti.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Conti.exe"; Description: "{cm:LaunchProgram,Conti}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Programmordner ganz wegräumen (auch alte Dateien von Updates). Die Daten
; liegen nicht hier und bleiben erhalten.
Type: filesandordirs; Name: "{app}"
