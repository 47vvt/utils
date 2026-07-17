<#
    Debug-AutopilotUpload.ps1
    Diagnostic companion to collect.ps1.

    Symptom being investigated: repeated runs of collect.ps1 on the same device keep
    reporting "SUCCESS - Device hardware hash uploaded to Intune" and never fall through
    to "SKIPPED - already registered", even though the broker is supposed to dedupe.

    collect.ps1 just reads the local serial + Autopilot hardware hash and POSTs them to
    the UOM broker (Azure Function); the broker decides uploaded vs exists vs error.
    So there are exactly two places this can break:

      1. CLIENT SIDE - the hardware hash isn't actually stable between runs, so the
         broker never receives the same payload twice and correctly treats every call
         as new.
      2. SERVER SIDE - the hash IS stable, but the broker's dedupe check is broken and
         always reports "uploaded" regardless.

    This script has three modes to isolate which one it is:

      -Mode HashStability   Collect serial+hash N times, no upload, compare fingerprints.
      -Mode BrokerReplay    POST one fixed serial+hash payload N times, print the FULL
                            raw HTTP response each time (not just the parsed status).
      -Mode FullRunLoop     Repeat the real collect+upload flow N times back-to-back,
                            logging hash fingerprint + broker result side by side.

    Run from an ELEVATED PowerShell session (hash collection needs admin).

    Examples:
        .\Debug-AutopilotUpload.ps1 -Mode HashStability -Iterations 5
        .\Debug-AutopilotUpload.ps1 -Mode BrokerReplay -Iterations 3
        .\Debug-AutopilotUpload.ps1 -Mode BrokerReplay -FromSampleFile $env:TEMP\autopilot-hash-samples-....json
        .\Debug-AutopilotUpload.ps1 -Mode FullRunLoop -Iterations 3 -DelaySeconds 15
#>

param(
    [ValidateSet('HashStability', 'BrokerReplay', 'FullRunLoop')]
    [string]$Mode = 'FullRunLoop',

    [int]$Iterations = 3,
    [int]$DelaySeconds = 10,

    [string]$FunctionURL = 'https://uom-autopilot-broker-cegydbdxdafff3aj.australiasoutheast-01.azurewebsites.net/api/UploadAutopilotHash?code=PU5xFmpJvDsuAO6cfyNMmA3Lm8GUHlHJ91ZA3Ge40oTNAzFu0v54Gg==',
    [string]$GroupTag = 'AAD',

    # BrokerReplay only: reuse a payload captured earlier (from HashStability's saved
    # JSON) instead of collecting a fresh one, so the exact same bytes go out every time.
    [string]$FromSampleFile
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Run this from an ELEVATED PowerShell session." -ForegroundColor Yellow
        throw 'Not elevated'
    }
}

function Get-DeviceHashSample {
    $serial = (Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop).SerialNumber
    $hash   = (Get-CimInstance -Namespace 'root/cimv2/mdm/dmmap' -ClassName 'MDM_DevDetail_Ext01' `
                -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -ErrorAction Stop).DeviceHardwareData
    [pscustomobject]@{
        Timestamp  = Get-Date
        Serial     = $serial
        Hash       = $hash
        HashSHA256 = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($hash)))
        HashLength = $hash.Length
    }
}

function Invoke-BrokerUpload {
    param([string]$Serial, [string]$Hash)
    $payload = @{ serialNumber = $Serial; hardwareHash = $Hash; groupTag = $GroupTag } | ConvertTo-Json
    try {
        $resp = Invoke-WebRequest -Method Post -Uri $FunctionURL -ContentType 'application/json' -Body $payload -ErrorAction Stop
        $status = $null
        try { $status = ($resp.Content | ConvertFrom-Json).status } catch {}
        [pscustomobject]@{ HttpStatus = [int]$resp.StatusCode; RawBody = $resp.Content; Status = $status }
    } catch {
        $code = $null
        try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        $body = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        [pscustomobject]@{ HttpStatus = $code; RawBody = $body; Status = 'ERROR' }
    }
}

switch ($Mode) {

    # ------------------------------------------------------------------
    'HashStability' {
        Assert-Admin
        Write-Host "Mode: HashStability -- collecting the hash $Iterations times, no upload." -ForegroundColor Cyan

        $samples = @()
        for ($i = 1; $i -le $Iterations; $i++) {
            Write-Host "==> Sample $i of $Iterations..." -ForegroundColor Cyan
            $samples += Get-DeviceHashSample
            if ($i -lt $Iterations) { Start-Sleep -Seconds $DelaySeconds }
        }

        Write-Host "`n--- Results ---" -ForegroundColor Cyan
        $samples | Format-Table Timestamp, Serial, HashLength, HashSHA256 -AutoSize

        $distinctHashes = $samples.HashSHA256 | Select-Object -Unique
        if ($distinctHashes.Count -eq 1) {
            Write-Host "`nSTABLE: hardware hash is IDENTICAL across all $Iterations reads." -ForegroundColor Green
            Write-Host "The issue is NOT the hash changing between runs -- check the broker/server-side dedupe logic (try -Mode BrokerReplay)." -ForegroundColor Green
        } else {
            Write-Host "`nUNSTABLE: hardware hash CHANGED between reads ($($distinctHashes.Count) distinct values seen)." -ForegroundColor Red
            Write-Host "This explains why the broker never recognizes the device as a duplicate -- each collection produces a 'new' hash." -ForegroundColor Red
        }

        $outFile = Join-Path $env:TEMP ("autopilot-hash-samples-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $samples | ConvertTo-Json -Depth 5 | Out-File -FilePath $outFile -Encoding utf8
        Write-Host "`nFull samples saved to: $outFile" -ForegroundColor Gray
        Write-Host "Reuse with: .\Debug-AutopilotUpload.ps1 -Mode BrokerReplay -FromSampleFile `"$outFile`"" -ForegroundColor Gray
    }

    # ------------------------------------------------------------------
    'BrokerReplay' {
        Write-Host "Mode: BrokerReplay -- POSTing ONE fixed payload $Iterations times." -ForegroundColor Cyan

        if ($FromSampleFile) {
            $sample = Get-Content $FromSampleFile -Raw | ConvertFrom-Json
            if ($sample -is [array]) { $sample = $sample[0] }
            $serial = $sample.Serial
            $hash   = $sample.Hash
            Write-Host "Loaded fixed payload from $FromSampleFile" -ForegroundColor Gray
        } else {
            Assert-Admin
            $s = Get-DeviceHashSample
            $serial = $s.Serial
            $hash   = $s.Hash
        }

        if ([string]::IsNullOrWhiteSpace($serial) -or [string]::IsNullOrWhiteSpace($hash)) {
            Write-Host "Serial or hash is empty -- aborting." -ForegroundColor Red
            return
        }
        Write-Host "Serial: $serial   Hash length: $($hash.Length) chars" -ForegroundColor Gray

        for ($i = 1; $i -le $Iterations; $i++) {
            Write-Host "`n==> POST attempt $i of $Iterations (byte-identical payload)..." -ForegroundColor Cyan
            $result = Invoke-BrokerUpload -Serial $serial -Hash $hash
            Write-Host "HTTP status: $($result.HttpStatus)" -ForegroundColor Gray
            Write-Host "Raw body: $($result.RawBody)" -ForegroundColor Gray
            $color = switch ($result.Status) { 'exists' {'Yellow'} 'uploaded' {'Green'} default {'Red'} }
            Write-Host "Parsed status: '$($result.Status)'" -ForegroundColor $color
            if ($i -lt $Iterations) { Start-Sleep -Seconds $DelaySeconds }
        }

        Write-Host "`nIf every attempt above returned 'uploaded' for the SAME serial+hash, the broker is not deduping correctly server-side -- escalate to whoever owns the Azure Function." -ForegroundColor Cyan
        Write-Host "If a later attempt returned 'exists', dedupe works for identical payloads and the real-world issue is that collect.ps1 produces a slightly different hash each run (try -Mode HashStability)." -ForegroundColor Cyan
    }

    # ------------------------------------------------------------------
    'FullRunLoop' {
        Assert-Admin
        Write-Host "Mode: FullRunLoop -- repeating the real collect+upload flow $Iterations times." -ForegroundColor Cyan

        $log = @()
        for ($i = 1; $i -le $Iterations; $i++) {
            Write-Host "`n==> Run $i of $Iterations" -ForegroundColor Cyan
            $s = Get-DeviceHashSample
            $result = Invoke-BrokerUpload -Serial $s.Serial -Hash $s.Hash

            $log += [pscustomobject]@{
                Run        = $i
                Timestamp  = Get-Date -Format 'HH:mm:ss'
                Serial     = $s.Serial
                HashSHA256 = $s.HashSHA256
                HttpStatus = $result.HttpStatus
                Status     = $result.Status
            }

            $color = switch ($result.Status) { 'exists' {'Yellow'} 'uploaded' {'Green'} default {'Red'} }
            Write-Host "Result: $($result.Status)" -ForegroundColor $color
            if ($i -lt $Iterations) { Start-Sleep -Seconds $DelaySeconds }
        }

        Write-Host "`n--- Summary ---" -ForegroundColor Cyan
        $log | Format-Table -AutoSize

        $distinctHashes = ($log.HashSHA256 | Select-Object -Unique).Count
        $distinctStatus = $log.Status | Select-Object -Unique

        if ($distinctHashes -gt 1) {
            Write-Host "`nDIAGNOSIS: hardware hash changed between runs ($distinctHashes distinct values) -- this is why the broker never sees a duplicate." -ForegroundColor Red
        } elseif ($distinctStatus.Count -eq 1 -and $distinctStatus -eq 'uploaded') {
            Write-Host "`nDIAGNOSIS: hash was IDENTICAL every run, but the broker returned 'uploaded' every time -- the broker/server dedupe logic is broken. Escalate to whoever owns the Azure Function." -ForegroundColor Red
        } elseif ($distinctStatus -contains 'exists') {
            Write-Host "`nDedupe worked at least once -- inconsistent behaviour, check timing/caching on the broker side." -ForegroundColor Yellow
        }

        $outFile = Join-Path $env:TEMP ("autopilot-fullrun-log-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $log | ConvertTo-Json -Depth 5 | Out-File -FilePath $outFile -Encoding utf8
        Write-Host "`nLog saved to: $outFile" -ForegroundColor Gray
    }
}
