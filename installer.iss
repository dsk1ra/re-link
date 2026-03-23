; Inno Setup installer script for Rust Remote Desktop - Windows Client
; This script packages the Flutter Windows release into a single .exe installer
; Requires: Inno Setup 6.0 or later

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

#define AppName "Rust Remote Desktop"
#define AppPublisher "dsk1ra"
#define AppExeName "application.exe"
#define AppPublisherURL "https://github.com/dsk1ra/rust-remote-desktop"
#define AppSupportURL "https://github.com/dsk1ra/rust-remote-desktop/issues"
#define AppUpdatesURL "https://github.com/dsk1ra/rust-remote-desktop/releases"
#define SourceDir "client\flutter\build\windows\x64\runner\Release"

[Setup]
; Installer metadata
AppId={{8F2D5B8E-4A7C-4F9D-B2E5-1A3C8F7B2D4E}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppPublisherURL}
AppSupportURL={#AppSupportURL}
AppUpdatesURL={#AppUpdatesURL}
AppVerName={#AppName} {#AppVersion}

; Installation paths and behavior
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=no
OutputBaseFilename=RustRemoteDesktopSetup
OutputDir=.
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
UsePreviousAppDir=yes
UninstallDisplayIcon={app}\{#AppExeName}

; Windows compatibility
MinVersion=10.0.10240

; Code signing (optional - remove if you don't have a certificate)
; SignTool=signtool

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunch"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Copy the entire Windows build output to the installation directory
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Exclude unwanted build artifacts (debug symbols, temporary files)
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: quicklaunch
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: dirifempty; Name: "{app}"
Type: filesandordirs; Name: "{app}\data"

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    { You can add post-installation code here if needed }
    { For example: extract configuration files, set environment variables, etc. }
  end;
end;
