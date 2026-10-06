$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Only run on a disposable Windows runner' }
$bundle = (Resolve-Path bundle).Path
$exe = Join-Path $bundle 'AZSign Remote.exe'
New-Item -ItemType Directory store-screenshots -Force | Out-Null
Start-Transcript -Path store-screenshots/capture-log.txt
$hosts = "$env:WINDIR\System32\drivers\etc\hosts"
$hostsOriginal = [IO.File]::ReadAllText($hosts)
$certificate = $null
$server = $null
$deviceId = [Guid]::NewGuid().ToString()
try {
    # Temporary trust and DNS affect only this disposable runner. Production is never accessed.
    Write-Host 'Creating temporary loopback certificate'
    $certificate = New-SelfSignedCertificate -DnsName 'app.azsign.com.br' -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddDays(1) -KeyExportPolicy Exportable
    Export-Certificate -Cert $certificate -FilePath fixture.cer | Out-Null
    Write-Host 'Trusting loopback fixture only in disposable machine store'
    & certutil -f -addstore Root fixture.cer
    if ($LASTEXITCODE -ne 0) { throw 'Fixture trust failed' }
    $env:AZSIGN_CAPTURE_PFX_PASSWORD = [Guid]::NewGuid().ToString()
    Export-PfxCertificate -Cert $certificate -FilePath fixture.pfx -Password (ConvertTo-SecureString $env:AZSIGN_CAPTURE_PFX_PASSWORD -AsPlainText -Force) | Out-Null
    Write-Host 'Configuring isolated DNS and firewall'
    [IO.File]::AppendAllText($hosts,"`r`n127.0.0.1 app.azsign.com.br remote.azsign.com.br rustdesk.azsign.com.br`r`n")
    Clear-DnsClientCache
    New-NetFirewallRule -DisplayName 'AZSign screenshot isolation' -Direction Outbound -Program $exe -Action Block -RemoteAddress Internet | Out-Null
    Write-Host 'Starting loopback fixture API'
    $server = Start-Process node -ArgumentList "$PSScriptRoot/server.cjs" -PassThru -RedirectStandardOutput store-screenshots/server-output.txt -RedirectStandardError store-screenshots/server-error.txt
    for ($i=0; $i -lt 40 -and !(Test-Path fixture-ready.txt); $i++) { Start-Sleep -Milliseconds 250 }
    if (!(Test-Path fixture-ready.txt)) { throw 'Fixture API did not start' }
    # Store the locale preference before launch, only in the temporary runner's profile.
    $config = Join-Path $env:APPDATA 'AZSignRemotePilot\config'
    New-Item -ItemType Directory $config -Force | Out-Null
    "[options]`nlang = 'ptbr'`ntheme = 'light'" | Set-Content "$config/AZSignRemotePilot_local.toml" -Encoding UTF8
    python "$PSScriptRoot/capture.py" login
    if ($LASTEXITCODE -ne 0) { throw 'Login capture failed' }
    & powershell -NoProfile -File "$PSScriptRoot/../msix/native-probe.ps1" -LibraryDir $bundle -ResultPath store-screenshots/demo-seed.json -DeviceId $deviceId -Mode seed
    if ($LASTEXITCODE -ne 0) { throw 'Fixture identity failed' }
    & powershell -NoProfile -File "$PSScriptRoot/../msix/native-probe.ps1" -LibraryDir $bundle -ResultPath store-screenshots/demo-write.json -DeviceId $deviceId -Mode write
    if ($LASTEXITCODE -ne 0) { throw 'Fixture storage failed' }
    python "$PSScriptRoot/capture.py" catalog
    if ($LASTEXITCODE -ne 0) { throw 'Catalog capture failed' }
    @{application='AZSign Remote';version='1.5.3';sourceCommit='fb3d155675b8b25e69025af6a7188fa0444de101';sourceRun='https://github.com/rgazeredo/rustdesk/actions/runs/37376782844';binarySha256=(Get-FileHash $exe).Hash;method='Unmodified Windows release executable. Loopback fixture CMS, fictional account and devices. No real remote sessions.'} | ConvertTo-Json | Set-Content store-screenshots/provenance.json
} finally {
    Get-Process | Where-Object { $_.Path -eq $exe } | Stop-Process -Force -ErrorAction SilentlyContinue
    if ($server) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    [IO.File]::WriteAllText($hosts,$hostsOriginal)
    Remove-NetFirewallRule -DisplayName 'AZSign screenshot isolation' -ErrorAction SilentlyContinue
    if ($certificate) {
        foreach ($store in @('CurrentUser\My','CurrentUser\Root','LocalMachine\Root')) { Remove-Item "Cert:\$store\$($certificate.Thumbprint)" -ErrorAction SilentlyContinue }
    }
    Remove-Item fixture.pfx -ErrorAction SilentlyContinue
    Stop-Transcript
}
