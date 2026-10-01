param(
    [Parameter(Mandatory)][string]$BundleDir,
    [Parameter(Mandatory)][string]$OutputDir,
    [Parameter(Mandatory)][string]$CertificateThumbprint,
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$Version = '1.5.2.0'
)
$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path $BundleDir).Path
foreach ($file in @('AZSign Remote.exe', 'librustdesk.dll', 'flutter_windows.dll', 'dylib_virtual_display.dll', 'msvcp140.dll', 'vcruntime140.dll', 'LICENSE-RustDesk.txt', 'BUILD-COMMIT.txt', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin')) {
    $path = Join-Path $bundle $file
    if (!(Test-Path $path -PathType Leaf) -or (Get-Item $path).Length -eq 0) { throw "Missing bundle input: $file" }
}
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory |
    Where-Object { $_.Name -match '^10\.0\.\d+\.0$' -and (Test-Path "$($_.FullName)\x64\makeappx.exe") -and (Test-Path "$($_.FullName)\x64\signtool.exe") } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$sdk) { throw 'Windows SDK packaging tools are required' }
$certificate = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint"
if ($certificate.Subject -ne 'CN=AZSign Remote MSIX Test' -or !$certificate.HasPrivateKey) { throw 'Expected the dedicated MSIX test signing certificate' }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$output = (Resolve-Path $OutputDir).Path
$package = Join-Path $output "AZSign-Remote-Test-$Version-x64.msix"
if (Test-Path $package) { throw "Refusing to overwrite package: $package" }
$stage = Join-Path $env:TEMP ('azsign-msix-' + [Guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item "$bundle\*" $stage -Recurse
    [xml]$manifest = Get-Content "$PSScriptRoot\AppxManifest.xml"
    $manifest.Package.Identity.Version = $Version
    $manifest.Save((Join-Path $stage 'AppxManifest.xml'))
    $assets = New-Item -ItemType Directory -Path "$stage\Assets"
    Add-Type -AssemblyName System.Drawing
    $repo = Split-Path (Split-Path (Split-Path $PSScriptRoot))
    $icon = [Drawing.Icon]::new("$repo\flutter\windows\runner\resources\app_icon.ico", 256, 256)
    $source = $icon.ToBitmap()
    try {
        foreach ($asset in @{StoreLogo = 50; Square44x44Logo = 44; Square150x150Logo = 150}.GetEnumerator()) {
            $bitmap = [Drawing.Bitmap]::new($asset.Value, $asset.Value)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.DrawImage($source, 0, 0, $asset.Value, $asset.Value)
                $bitmap.Save("$($assets.FullName)\$($asset.Key).png", [Drawing.Imaging.ImageFormat]::Png)
            } finally { $graphics.Dispose(); $bitmap.Dispose() }
        }
    } finally { $source.Dispose(); $icon.Dispose() }
    & "$($sdk.FullName)\x64\makeappx.exe" pack /d $stage /p $package /o
    if ($LASTEXITCODE -ne 0) { throw 'MSIX manifest validation/packing failed' }
    & "$($sdk.FullName)\x64\signtool.exe" sign /fd SHA256 /sha1 $CertificateThumbprint /s My $package
    if ($LASTEXITCODE -ne 0) { throw 'MSIX signing failed' }
    $hash = (Get-FileHash $package -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $(Split-Path $package -Leaf)" | Set-Content "$package.sha256" -Encoding ascii
} finally {
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
}
