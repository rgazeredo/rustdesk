param(
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$BundleDir
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run only on a disposable Windows CI runner' }
$installerPath = (Resolve-Path $Installer).Path
$bundle = (Resolve-Path $BundleDir).Path
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\AZSign Remote'
$exe = Join-Path $installDir 'AZSign Remote.exe'
$protocol = 'HKCU:\Software\Classes\azsign-remote'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AZSignRemote_is1'
$startLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'AZSign Remote.lnk'
$desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AZSign Remote.lnk'
$secureStore = Join-Path $env:LOCALAPPDATA 'AZSignRemotePilot\SecureStore'
$sentinel = Join-Path $secureStore 'installer-test-preserve.txt'
$token = [Guid]::NewGuid().ToString()
New-Item -ItemType Directory $secureStore -Force | Out-Null
Set-Content $sentinel $token

function Assert-Preserved {
    if ((Get-Content $sentinel -Raw).Trim() -ne $token) { throw 'Existing user data changed' }
}
function Install-Remote {
    param([string]$Label)
    $log = Join-Path $env:RUNNER_TEMP "remote-install-$Label.log"
    $process = Start-Process $installerPath -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/TASKS=desktopicon', "/LOG=`"$log`"") -PassThru
    if (!$process.WaitForExit(120000)) { $process.Kill(); throw 'Installation timed out' }
    if ($process.ExitCode -ne 0) { throw "Installation failed: $($process.ExitCode); $log" }
    foreach ($file in Get-ChildItem $bundle -File -Recurse) {
        $relative = [IO.Path]::GetRelativePath($bundle, $file.FullName)
        $installed = Join-Path $installDir $relative
        if (!(Test-Path $installed) -or (Get-FileHash $installed).Hash -ne (Get-FileHash $file.FullName).Hash) {
            throw "Installed payload differs: $relative"
        }
    }
    if (!(Test-Path $uninstallKey)) { throw 'Missing Apps & Features registration' }
    foreach ($link in @($startLink, $desktopLink)) {
        if (!(Test-Path $link)) { throw "Missing shortcut: $link" }
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
        if ($shortcut.TargetPath -ne $exe -or $shortcut.WorkingDirectory -ne $installDir) { throw "Incorrect shortcut: $link" }
    }
    if ((Get-Item $protocol).GetValue('URL Protocol') -ne '') { throw 'Missing protocol marker' }
    if ((Get-Item "$protocol\shell\open\command").GetValue('') -ne ('"' + $exe + '" "%1"')) { throw 'Incorrect installed protocol command' }
    Assert-Preserved
}
function Uninstall-Remote {
    $uninstaller = (Get-ItemPropertyValue $uninstallKey 'UninstallString').Trim('"')
    if (!(Test-Path $uninstaller -PathType Leaf)) { throw "Registered uninstaller is missing: $uninstaller" }
    Write-Output "Testing registered uninstaller: $uninstaller"
    $process = Start-Process $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -PassThru
    if (!$process.WaitForExit(120000)) { $process.Kill(); throw 'Uninstall timed out' }
    if ($process.ExitCode -ne 0) { throw "Uninstall failed: $($process.ExitCode)" }
    if ((Test-Path $exe) -or (Test-Path $uninstallKey) -or (Test-Path $startLink) -or (Test-Path $desktopLink)) { throw 'Uninstall left application, registration or shortcuts' }
    Assert-Preserved
}

Install-Remote 'fresh'
$probe = Start-Process $exe -ArgumentList '--version' -PassThru
if (!$probe.WaitForExit(30000)) { $probe.Kill(); throw 'Installed native loader timed out' }
if ($probe.ExitCode -ne 0) { throw 'Installed native loader failed' }
$app = Start-Process $exe -PassThru
try {
    Start-Sleep -Seconds 15
    if ($app.HasExited) { throw 'Installed application exited during startup' }
    Start-Process 'azsign-remote://connection/new/123456789'
    Start-Sleep -Seconds 5
    $windows = @(Get-Process | Where-Object { $_.Path -eq $exe -and $_.MainWindowHandle -ne 0 })
    if ($windows.Count -ne 1 -or $windows[0].Id -ne $app.Id) { throw 'Installed link did not reuse the application window' }
} finally {
    foreach ($process in @(Get-Process | Where-Object { $_.Path -eq $exe })) {
        Stop-Process -Id $process.Id -Force -ErrorAction Continue
    }
}

# Reinstallation repairs payload files but must leave user data and foreign files.
$foreignFile = Join-Path $installDir 'customer-notes.txt'
Set-Content $foreignFile $token
Set-Content "$installDir/BUILD-COMMIT.txt" 'damaged'
Install-Remote 'repair'
Uninstall-Remote
if (Test-Path $protocol) { throw 'Uninstall left its own URL protocol' }
if ((Get-Content $foreignFile -Raw).Trim() -ne $token) { throw 'Uninstall deleted an unowned file' }

# A portable copy can take over the URL protocol; its registration must survive.
Install-Remote 'portable-coexistence'
$portableCommand = '"C:\Portable Remote\AZSign Remote.exe" "%1"'
Set-Item "$protocol\shell\open\command" $portableCommand
Uninstall-Remote
if ((Get-Item "$protocol\shell\open\command").GetValue('') -ne $portableCommand) { throw 'Uninstall removed another copy protocol' }
Remove-Item $sentinel, $foreignFile
Write-Output 'Installer passed: payload hashes, shortcuts, registration, loader, warm link, repair, user data preservation, uninstall and portable coexistence.'
