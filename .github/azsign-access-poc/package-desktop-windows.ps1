param(
    [Parameter(Mandatory)][string]$BundleDir,
    [Parameter(Mandatory)][string]$OutputDir,
    [string]$Compiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)
$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path $BundleDir).Path
$repo = Split-Path (Split-Path $PSScriptRoot)
$versionLine = Select-String -Path "$repo/flutter/pubspec.yaml" -Pattern '^version: (\d+\.\d+\.\d+)\+'
if (!$versionLine) { throw 'Missing desktop version' }
$version = $versionLine.Matches[0].Groups[1].Value
foreach ($file in @('AZSign Remote.exe', 'librustdesk.dll', 'flutter_windows.dll', 'dylib_virtual_display.dll', 'LICENSE-RustDesk.txt', 'BUILD-COMMIT.txt', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin')) {
    $path = Join-Path $bundle $file
    if (!(Test-Path $path -PathType Leaf) -or (Get-Item $path).Length -eq 0) { throw "Missing bundle input: $file" }
}
if (!(Test-Path $Compiler -PathType Leaf)) { throw "Inno Setup 6 compiler not found: $Compiler" }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$output = (Resolve-Path $OutputDir).Path
$installer = Join-Path $output "AZSign-Remote-Setup-$version-windows-x64.exe"
if (Test-Path $installer) { throw "Refusing to overwrite existing installer: $installer" }
& $Compiler "/DBundleDir=$bundle" "/DAppVersion=$version" "/DOutputDir=$output" "$PSScriptRoot/windows-installer.iss"
if ($LASTEXITCODE -ne 0 -or !(Test-Path $installer)) { throw 'Installer compilation failed' }
$hash = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $(Split-Path $installer -Leaf)" | Set-Content "$installer.sha256" -Encoding ascii
Write-Output "Installer: $installer"
