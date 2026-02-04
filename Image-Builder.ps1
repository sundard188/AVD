# =====================================================
# AIB Bootstrapper – Image Customization (PRODUCTION)
# =====================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------- Configuration ----------------
$StorageAccount = "azuremarketplacetesting"
$Container      = "image"
$ScriptName     = "02-App-Install-FINAL.ps1"

$TempPath   = "C:\AIB"
$ScriptPath = Join-Path $TempPath $ScriptName
$BlobUri    = "https://$StorageAccount.blob.core.windows.net/$Container/$ScriptName"

Write-Host "=============================================="
Write-Host "AIB Bootstrapper (Managed Identity)"
Write-Host "=============================================="

# ---------------- Prep ----------------
if (-not (Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
}

# ---------------- Get IMDS token ----------------
Write-Host "Requesting OAuth2 token from IMDS..."

$imdsUri = "http://169.254.169.254/metadata/identity/oauth2/token" +
           "?api-version=2021-01-01&resource=https://storage.azure.com"

try {
    $tokenResponse = Invoke-RestMethod `
        -Uri $imdsUri `
        -Headers @{ Metadata = "true" } `
        -Method GET
}
catch {
    throw "IMDS token request failed: $($_.Exception.Message)"
}

$bearerToken = $tokenResponse.access_token
if (-not $bearerToken) {
    throw "IMDS returned no access token. Managed Identity not available."
}

Write-Host "IMDS token acquired."

# ---------------- Download script ----------------
Write-Host "Downloading app install script from blob..."
Write-Host "URI: $BlobUri"

$blobHeaders = @{
    Authorization  = "Bearer $bearerToken"
    "x-ms-version" = "2021-08-06"
}

try {
    Invoke-WebRequest `
        -Uri $BlobUri `
        -Headers $blobHeaders `
        -OutFile $ScriptPath `
        -UseBasicParsing
}
catch {
    throw "Blob download failed: $($_.Exception.Message)"
}

# ---------------- Validate download ----------------
if (-not (Test-Path $ScriptPath)) {
    throw "Downloaded script not found at $ScriptPath"
}

$fileSize = (Get-Item $ScriptPath).Length
if ($fileSize -lt 512) {
    Write-Host "Downloaded file content (for diagnostics):"
    Get-Content $ScriptPath | Write-Host
    throw "Downloaded script too small ($fileSize bytes). Likely auth or HTML error."
}

Write-Host "Download validated ($fileSize bytes)."

# ---------------- Execute child script (HARD FAIL MODE) ----------------
Write-Host "Executing application install script..."

$childCommand = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
& '$ScriptPath'
"@

powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -Command $childCommand

if ($LASTEXITCODE -ne 0) {
    throw "Child install script failed with exit code $LASTEXITCODE"
}

Write-Host "Application installation completed successfully."
Write-Host "AIB customization step finished cleanly."
