# =====================================================
# AIB Bootstrapper – FINAL (MI → Blob → Install)
# AIB / Packer SAFE
# =====================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TranscriptPath = $null

try {
    # ---------------- Configuration ----------------
    $StorageAccount = "azuremarketplacetesting"
    $Container      = "image"
    $InstallerName  = "02-App-Install-FINAL.ps1"

    $InstallerUri   = "https://$StorageAccount.blob.core.windows.net/$Container/$InstallerName"
    $TempPath       = "C:\AIB"
    $InstallerPath  = Join-Path $TempPath $InstallerName

    # ---------------- Prep ----------------
    if (-not (Test-Path $TempPath)) {
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
    }

    $TranscriptPath = Join-Path $TempPath "bootstrapper-transcript.log"
    Start-Transcript -Path $TranscriptPath -Force

    Write-Host "=============================================="
    Write-Host "AIB Bootstrapper - Managed Identity Mode"
    Write-Host "=============================================="

    # ---------------- IMDS Readiness ----------------
    Write-Host "Waiting for IMDS..."

    $imdsReady = $false
    for ($i = 1; $i -le 12; $i++) {
        try {
            Invoke-RestMethod `
                -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" `
                -Headers @{ Metadata = "true" } `
                -TimeoutSec 5 | Out-Null

            $imdsReady = $true
            break
        }
        catch {
            Write-Host "IMDS not ready (attempt $i)"
            Start-Sleep -Seconds 5
        }
    }

    if (-not $imdsReady) {
        throw "IMDS did not become ready"
    }

    Write-Host "IMDS is reachable"

    # ---------------- Identity Validation ----------------
    Write-Host "Validating managed identity attachment..."

    $identityInfo = Invoke-RestMethod `
        -Uri "http://169.254.169.254/metadata/instance/identity?api-version=2021-02-01" `
        -Headers @{ Metadata = "true" }

    if (-not $identityInfo) {
        throw "No managed identity metadata returned"
    }

    Write-Host "Identity type detected: $($identityInfo.type)"

    if ($identityInfo.type -notmatch "UserAssigned") {
        throw "Expected user-assigned managed identity but none detected"
    }

    Write-Host "User-assigned identity confirmed"

    # ---------------- Token Acquisition ----------------
    Write-Host "Requesting Managed Identity token..."

    $resource = [System.Uri]::EscapeDataString("https://storage.azure.com/")
    $tokenUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=$resource"

    $accessToken = $null

    for ($i = 1; $i -le 10; $i++) {
        try {
            $tokenResponse = Invoke-RestMethod `
                -Uri $tokenUri `
                -Headers @{ Metadata = "true" } `
                -Method GET `
                -TimeoutSec 10

            if ($tokenResponse.access_token) {
                $accessToken = $tokenResponse.access_token
                break
            }
        }
        catch {
            Write-Host "Token request failed (attempt $i)"
            Start-Sleep -Seconds 5
        }
    }

    if (-not $accessToken) {
        throw "Managed Identity token acquisition failed"
    }

    Write-Host "Managed Identity token acquired"

    # ---------------- Blob Access Validation ----------------
    Write-Host "Validating Blob access permissions..."

    $authHeaders = @{
        Authorization  = "Bearer $accessToken"
        "x-ms-version" = "2021-08-06"
    }

    try {
        Invoke-WebRequest `
            -Uri $InstallerUri `
            -Headers $authHeaders `
            -Method Head `
            -TimeoutSec 30 | Out-Null
    }
    catch {
        throw "Blob access denied. Verify Storage Blob Data Reader role."
    }

    Write-Host "Blob access confirmed"

    # ---------------- Download Installer ----------------
    Write-Host "Downloading installer from Blob..."

    Invoke-WebRequest `
        -Uri $InstallerUri `
        -Headers $authHeaders `
        -OutFile $InstallerPath `
        -TimeoutSec 120

    if (-not (Test-Path $InstallerPath)) {
        throw "Installer was not downloaded"
    }

    $fileSize = (Get-Item $InstallerPath).Length
    if ($fileSize -lt 1024) {
        throw "Installer file size invalid"
    }

    Write-Host "Installer downloaded successfully"

    # ---------------- Execute Installer ----------------
    Write-Host "Executing installer..."

    powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $InstallerPath

    if ($LASTEXITCODE -ne 0) {
        throw "Installer execution failed"
    }

    Write-Host "Installer execution completed successfully"
    Write-Host "Bootstrapper completed successfully"

    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Error "BOOTSTRAPPER FAILED"
    Write-Error $_.Exception.Message

    if ($TranscriptPath) {
        Stop-Transcript | Out-Null
    }

    exit 1
}
