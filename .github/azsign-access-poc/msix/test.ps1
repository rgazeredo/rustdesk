param(
    [Parameter(Mandatory)][string]$PackageDir,
    [Parameter(Mandatory)][string]$BundleDir,
    [string]$IdentityName = 'AZSign.Remote.Test',
    [string]$InitialVersion = '1.5.2.0',
    [string]$UpgradeVersion = '1.5.2.1'
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run only on a disposable Windows CI runner' }
$packageDir = (Resolve-Path $PackageDir).Path
$bundle = (Resolve-Path $BundleDir).Path
$results = (New-Item -ItemType Directory -Path msix-results -Force).FullName
$name = $IdentityName
if (Get-AppxPackage -Name $name) { throw 'Test package already installed' }
$legacy = Join-Path $env:LOCALAPPDATA 'AZSignRemotePilot\SecureStore'
if (Test-Path $legacy) { throw 'Refusing to overwrite pre-existing credentials' }
$deviceId = [Guid]::NewGuid().ToString()
$powershell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$probe = Join-Path $PSScriptRoot 'native-probe.ps1'
$certificate = Import-Certificate -FilePath "$packageDir\AZSign-Remote-Test.cer" -CertStoreLocation Cert:\LocalMachine\TrustedPeople

function Invoke-Probe {
    param([string]$Mode, [string]$Label, $Package = $null)
    $result = Join-Path $results "$Label.json"
    $library = $bundle
    $expected = ''
    if ($Package) { $library = $Package.InstallLocation; $expected = $Package.PackageFullName }
    $arguments = "-NoProfile -File `"$probe`" -LibraryDir `"$library`" -ResultPath `"$result`" -DeviceId $deviceId -Mode $Mode"
    if ($Package) {
        $arguments += " -ExpectedPackage `"$expected`""
        Invoke-CommandInDesktopPackage -PackageFamilyName $Package.PackageFamilyName -AppId Remote -Command $powershell -Args $arguments -PreventBreakaway
    } else {
        $process = Start-Process $powershell -ArgumentList $arguments -PassThru
    }
    $deadline = (Get-Date).AddSeconds(45)
    while (!(Test-Path $result) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
    if (!(Test-Path $result)) { throw "Native probe timed out: $Label" }
    # The child writes a short JSON result at exit, never plaintext credentials.
    Start-Sleep -Milliseconds 300
    $value = Get-Content $result -Raw | ConvertFrom-Json
    if (!$value.ok) { throw "Native probe failed ($Label): $($value.error)" }
    return $value
}
function Stop-Remote {
    param($Package)
    foreach ($process in @(Get-Process | Where-Object { $_.Path -eq "$($Package.InstallLocation)\AZSign Remote.exe" })) {
        Stop-Process -Id $process.Id -Force
    }
}
function Test-Activation {
    param($Package)
    $exe = "$($Package.InstallLocation)\AZSign Remote.exe"
    # Exercise actual shell protocol activation, rather than launching the exe directly.
    Start-Process 'azsign-remote://connection/new/123456789'
    Start-Sleep -Seconds 15
    $windows = @(Get-Process | Where-Object { $_.Path -eq $exe -and $_.MainWindowHandle -ne 0 })
    if ($windows.Count -ne 1) { throw "Cold MSIX protocol launch produced $($windows.Count) windows" }
    $firstId = $windows[0].Id
    if (!('RemoteProcessIdentity' -as [type])) { Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class RemoteProcessIdentity {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetPackageFullName(IntPtr process, ref uint length, StringBuilder name);
}
'@
    }
    [uint32]$length = 512
    $identity = New-Object Text.StringBuilder 512
    if ([RemoteProcessIdentity]::GetPackageFullName($windows[0].Handle, [ref]$length, $identity) -ne 0 -or $identity.ToString() -ne $Package.PackageFullName) { throw 'Desktop window does not have MSIX identity' }
    Start-Process 'azsign-remote://connection/new/123456789'
    Start-Sleep -Seconds 5
    $windows = @(Get-Process | Where-Object { $_.Path -eq $exe -and $_.MainWindowHandle -ne 0 })
    if ($windows.Count -ne 1 -or $windows[0].Id -ne $firstId) { throw 'Warm MSIX link did not reuse the original window' }
    Stop-Remote $Package
}
function Save-Protocol {
    param([string]$Label)
    $key = 'HKCU:\Software\Classes\azsign-remote'
    if (Test-Path $key) {
        Get-Item $key | Format-List * | Out-File "$results\protocol-$Label.txt"
        Get-ChildItem $key -Recurse | ForEach-Object { Get-ItemProperty $_.PSPath } | Format-List * | Out-File "$results\protocol-$Label.txt" -Append
    } else { 'No unpackaged protocol key' | Set-Content "$results\protocol-$Label.txt" }
}

try {
    Invoke-Probe 'seed' 'unpackaged-baseline' | Out-Null
    $legacyFile = Join-Path $legacy 'azsign_desktop_device_id.dpapi'
    $legacyHash = (Get-FileHash $legacyFile).Hash
    Add-AppxPackage -Path "$packageDir\AZSign-Remote-Test-$InitialVersion-x64.msix"
    $package = Get-AppxPackage -Name $name
    if (!$package -or $package.Version -ne $InitialVersion) { throw 'Initial deployment failed' }
    $manifest = Get-AppxPackageManifest $package.PackageFullName
    if ($manifest.Package.Applications.Application.Extensions.Extension.Protocol.Name -ne 'azsign-remote') { throw 'Missing manifest protocol' }
    Save-Protocol 'installed'
    Test-Activation $package
    Save-Protocol 'launched'
    $write = Invoke-Probe 'write' 'packaged-write' $package
    $read = Invoke-Probe 'read' 'packaged-restart' $package
    if ($write.csrSha256 -ne $read.csrSha256) { throw 'Native private key changed after restart' }
    Add-AppxPackage -Path "$packageDir\AZSign-Remote-Test-$UpgradeVersion-x64.msix"
    $package = Get-AppxPackage -Name $name
    if ($package.Version -ne $UpgradeVersion) { throw 'MSIX upgrade failed' }
    $upgrade = Invoke-Probe 'read' 'packaged-upgrade' $package
    if ($write.csrSha256 -ne $upgrade.csrSha256) { throw 'Native private key changed after upgrade' }
    Invoke-Probe 'cleanup' 'packaged-token-delete' $package | Out-Null
    Test-Activation $package
    Save-Protocol 'upgraded'
    Remove-AppxPackage -Package $package.PackageFullName
    Save-Protocol 'removed'
    if (Get-AppxPackage -Name $name) { throw 'Package removal failed' }
    $commandKey = 'HKCU:\Software\Classes\azsign-remote\shell\open\command'
    if (Test-Path $commandKey) {
        $command = (Get-Item $commandKey).GetValue('')
        if ($command -like '*WindowsApps*AZSign Remote.exe*') { throw "Uninstall left a stale executable association: $command" }
    }
    if (!(Test-Path $legacyFile) -or (Get-FileHash $legacyFile).Hash -ne $legacyHash) { throw 'Legacy credentials were changed or removed' }
    Invoke-Probe 'seed' 'unpackaged-after-uninstall' | Out-Null
    'PASS: deployment, native DPAPI, legacy identity read, key persistence, upgrade, cold/warm protocol activation with real MSIX identity, protocol cleanup and uninstall.' | Set-Content "$results\summary.txt"
    Get-Content "$results\summary.txt"
} finally {
    $package = Get-AppxPackage -Name $name
    if ($package) { Stop-Remote $package; Remove-AppxPackage -Package $package.PackageFullName }
    Remove-Item "Cert:\LocalMachine\TrustedPeople\$($certificate.Thumbprint)"
}
