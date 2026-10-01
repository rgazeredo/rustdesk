#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif

[Setup]
AppId=AZSignRemote
AppName=AZSign Remote
AppVersion={#AppVersion}
AppPublisher=AZSign
AppPublisherURL=https://azsign.com.br
DefaultDirName={localappdata}\Programs\AZSign Remote
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=AZSign-Remote-Setup-{#AppVersion}-windows-x64
SetupIconFile=..\..\flutter\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\AZSign Remote.exe
UninstallDisplayName=AZSign Remote
LicenseFile={#BundleDir}\LICENSE-RustDesk.txt
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ChangesAssociations=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\AZSign Remote"; Filename: "{app}\AZSign Remote.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\AZSign Remote"; Filename: "{app}\AZSign Remote.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Classes\azsign-remote"; ValueType: string; ValueName: ""; ValueData: "URL:AZSign Remote"
Root: HKCU; Subkey: "Software\Classes\azsign-remote"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\azsign-remote\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\AZSign Remote.exe"" ""%1"""

[Run]
Filename: "{app}\AZSign Remote.exe"; Description: "{cm:LaunchProgram,AZSign Remote}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Command: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    { A portable copy may have claimed the protocol after installation. }
    if RegQueryStringValue(HKCU, 'Software\Classes\azsign-remote\shell\open\command', '', Command) then
      if CompareText(Command, ExpandConstant('"{app}\AZSign Remote.exe" "%1"')) = 0 then
        if not RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\azsign-remote') then
          Log('Could not remove AZSign Remote protocol registration');
  end;
end;
