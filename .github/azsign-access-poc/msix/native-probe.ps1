param(
    [Parameter(Mandatory)][string]$LibraryDir,
    [Parameter(Mandatory)][string]$ResultPath,
    [Parameter(Mandatory)][string]$DeviceId,
    [ValidateSet('seed', 'write', 'read', 'cleanup')][string]$Mode,
    [string]$ExpectedPackage = ''
)
$ErrorActionPreference = 'Stop'
try {
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class RemoteNativeProbe {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetDllDirectory(string path);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetCurrentPackageFullName(ref uint length, StringBuilder name);
    [DllImport("librustdesk.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr azsign_windows_dispatch([MarshalAs(UnmanagedType.LPStr)] string request);
    [DllImport("librustdesk.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void azsign_windows_free(IntPtr value);
}
'@
    [uint32]$length = 512
    $name = New-Object Text.StringBuilder 512
    $status = [RemoteNativeProbe]::GetCurrentPackageFullName([ref]$length, $name)
    if ($ExpectedPackage) {
        if ($status -ne 0 -or $name.ToString() -ne $ExpectedPackage) { throw 'Probe does not have the expected package identity' }
    } elseif ($status -ne 15700) { throw 'Baseline probe must be unpackaged' }
    if (![RemoteNativeProbe]::SetDllDirectory($LibraryDir)) { throw 'Cannot configure native DLL lookup' }
    function Invoke-Native {
        param([string]$Method, [hashtable]$Arguments)
        $request = @{method = $Method; args = $Arguments} | ConvertTo-Json -Compress
        $pointer = [RemoteNativeProbe]::azsign_windows_dispatch($request)
        if ($pointer -eq [IntPtr]::Zero) { throw 'Native dispatch returned null' }
        try { $response = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($pointer) | ConvertFrom-Json }
        finally { [RemoteNativeProbe]::azsign_windows_free($pointer) }
        if (!$response.ok) { throw "Native operation failed: $Method" }
        return $response.value
    }
    $deviceKey = @{key = 'azsign_desktop_device_id'}
    $tokenKey = @{key = 'azsign_desktop_access_token'}
    if ($Mode -eq 'seed') {
        Invoke-Native 'azsignSecureWrite' @{key = $deviceKey.key; value = $DeviceId} | Out-Null
    }
    if ((Invoke-Native 'azsignSecureRead' $deviceKey) -ne $DeviceId) { throw 'Device identity was not preserved across packaging' }
    $csrHash = $null
    if ($Mode -eq 'write' -or $Mode -eq 'read') {
        $value = 'MSIX-CI-NOT-A-REAL-TOKEN-' + $DeviceId
        if ($Mode -eq 'write') { Invoke-Native 'azsignSecureWrite' @{key = $tokenKey.key; value = $value} | Out-Null }
        if ((Invoke-Native 'azsignSecureRead' $tokenKey) -ne $value) { throw 'DPAPI round trip failed' }
        $identity = Invoke-Native 'azsignIdentityPrepare' @{identity_id = $DeviceId}
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $csrHash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity.csr))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    }
    if ($Mode -eq 'cleanup') {
        Invoke-Native 'azsignSecureDelete' $tokenKey | Out-Null
        if ($null -ne (Invoke-Native 'azsignSecureRead' $tokenKey)) { throw 'Token deletion failed' }
    }
    @{ok = $true; mode = $Mode; package = $name.ToString(); csrSha256 = $csrHash} | ConvertTo-Json | Set-Content $ResultPath
} catch {
    @{ok = $false; error = $_.Exception.Message; mode = $Mode} | ConvertTo-Json | Set-Content $ResultPath
    exit 1
}
