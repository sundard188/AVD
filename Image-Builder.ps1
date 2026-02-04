# =====================================================
# AIB Bootstrapper – Plain Style (MI → Blob → Install)
# Safe for Azure Image Builder / Packer
# =====================================================

$ErrorActionPreference = "Stop"
$TranscriptPath = $null

# ---------------- Configuration ----------------
$StorageAccount = "azuremarketplacetesting"
$Container      = "image"
$InstallerName  = "02-App-Install-FINAL.ps1"

$InstallerUri  = "https://$StorageAccount.blob.core.windows.net/$Container/$InstallerName"
$TempPath      = "C:\AIB"
$InstallerPath = Join-Path $TempPath $InstallerName

# ---------------- Prep ----------------
if (-not (Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
}

$TranscriptPath = Join-Path $TempPath "bootstrapper-transcript.log"
Start-Transcript -Path $TranscriptPath -Force

Write-Host "=============================================="
Write-Host "AIB Bootstrapper - Managed Identity Mode"
Write-Host "=============================================="

# ---------------- IMDS Check ----------------
Write-Host "Waiting for IMDS..."
$imdsReady = $false

for ($i = 1; $i -le 10; $i++) {
    try {
        Invoke-RestMethod `
            -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" `
            -Headers @{ Metadata = "true" } `
            -TimeoutSec 5 | Out-Null

        $imdsReady = $true
        break
    }
    catch {
        Write-Host "IMDS not ready, retrying..."
        Start-Sleep -Seconds 5
    }
}

if (-not $imdsReady) {
    Write-Host "ERROR: IMDS not reachable"
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "IMDS is reachable"

# ---------------- Managed Identity Validation ----------------
Write-Host "Validating managed identity attachment..."

try {
    $identityInfo = Invoke-RestMethod `
        -Uri "http://169.254.169.254/metadata/instance/identity?api-version=2021-02-01" `
        -Headers @{ Metadata = "true" }
}
catch {
    Write-Host "ERROR: Unable to query managed identity metadata"
    Stop-Transcript | Out-Null
    exit 1
}

if (-not $identityInfo -or -not $identityInfo.type) {
    Write-Host "ERROR: No managed identity attached"
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "Managed identity detected: $($identityInfo.type)"

# ---------------- Token Acquisition ----------------
Write-Host "Requesting access token for Storage..."

$resource  = [System.Uri]::EscapeDataString("https://storage.azure.com/")
$tokenUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=$resource"
$accessToken = $null

for ($i = 1; $i -le 10; $i++) {
    try {
        $tokenResponse = Invoke-RestMethod `
            -Uri $tokenUri `
            -Headers @{ Metadata = "true" } `
            -TimeoutSec 10

        if ($tokenResponse.access_token) {
            $accessToken = $tokenResponse.access_token
            break
        }
    }
    catch {
        Write-Host "Token request failed, retrying..."
        Start-Sleep -Seconds 5
    }
}

if (-not $accessToken) {
    Write-Host "ERROR: Failed to obtain managed identity token"
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "Managed identity token acquired"

# ---------------- Blob Access Validation ----------------
Write-Host "Validating Blob access..."

$headers = @{
    Authorization  = "Bearer $accessToken"
    "x-ms-version" = "2021-08-06"
}

try {
    Invoke-WebRequest `
        -Uri $InstallerUri `
        -Headers $headers `
        -Method Head `
        -TimeoutSec 30 | Out-Null
}
catch {
    Write-Host "ERROR: Blob access denied"
    Write-Host "Ensure the identity has 'Storage Blob Data Reader'"
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "Blob access confirmed"

# ---------------- Download Installer ----------------
Write-Host "Downloading installer script..."

try {
    Invoke-WebRequest `
        -Uri $InstallerUri `
        -Headers $headers `
        -OutFile $InstallerPath `
        -TimeoutSec 120
}
catch {
    Write-Host "ERROR: Failed to download installer"
    Stop-Transcript | Out-Null
    exit 1
}

if (-not (Test-Path $InstallerPath)) {
    Write-Host "ERROR: Installer file not found after download"
    Stop-Transcript | Out-Null
    exit 1
}

$fileSize = (Get-Item $InstallerPath).Length
if ($fileSize -lt 1024) {
    Write-Host "ERROR: Installer file is unexpectedly small"
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "Installer downloaded successfully"

# ---------------- Execute Installer ----------------
Write-Host "Executing installer script..."

try {
    & $InstallerPath
}
catch {
    Write-Host "ERROR: Installer execution failed"
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "Installer execution completed successfully"
Write-Host "Bootstrapper completed successfully"

Stop-Transcript | Out-Null
exit 0
