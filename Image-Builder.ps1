# =====================================================
# AIB Bootstrapper – Image Customization Only
# =====================================================
$ErrorActionPreference = 'Stop'

# -------- Configuration --------
$StorageAccount = "azuremarketplacetesting"
$Container      = "image"
$ScriptName     = "02-App-Install-FINAL.ps1"
$TempPath       = "C:\AIB"
$ScriptPath     = Join-Path $TempPath $ScriptName
$BlobUri        = "https://$StorageAccount.blob.core.windows.net/$Container/$ScriptName"

Write-Host "=============================================="
Write-Host "AIB Bootstrapper – Managed Identity Mode"
Write-Host "=============================================="

# -------- Prep --------
if (-not (Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory | Out-Null
}

# -------- Step 1: get a Bearer token from IMDS --------
Write-Host "Requesting OAuth2 token from IMDS..." -ForegroundColor Yellow

$imdsUri = "http://169.254.169.254/metadata/identity/oauth2/token" +
           "?api-version=2021-01-01&resource=https://storage.azure.com"

$tokenResponse = Invoke-RestMethod `
    -Uri     $imdsUri `
    -Headers @{ Metadata = "true" } `
    -Method  GET

$bearerToken = $tokenResponse.access_token

if (-not $bearerToken) {
    Write-Host "ERROR: IMDS returned no access_token. Managed identity may not be attached." -ForegroundColor Red
    exit 1
}

Write-Host "Token acquired." -ForegroundColor Green

# -------- Step 2: download the script using that token --------
Write-Host "Downloading app install script from blob..." -ForegroundColor Yellow
Write-Host "URI: $BlobUri" -ForegroundColor Gray

$blobHeaders = @{
    Authorization = "Bearer $bearerToken"
    "x-ms-version" = "2021-08-06"
}

Invoke-WebRequest `
    -Uri     $BlobUri `
    -Headers $blobHeaders `
    -OutFile $ScriptPath `
    -UseBasicParsing

# -------- Verify the download --------
if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERROR: Script file not found at $ScriptPath." -ForegroundColor Red
    exit 1
}

$fileSize = (Get-Item $ScriptPath).Length
if ($fileSize -lt 100) {
    Write-Host "ERROR: Downloaded file is too small ($fileSize bytes) — likely an auth error page." -ForegroundColor Red
    Get-Content $ScriptPath | Write-Host
    exit 1
}

Write-Host ("Download successful ({0} bytes)." -f $fileSize) -ForegroundColor Green

# -------- Execute installer --------
Write-Host "Executing app installation script..." -ForegroundColor Yellow

powershell.exe `
    -ExecutionPolicy Bypass `
    -NoProfile `
    -File $ScriptPath

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: App installation script exited with code $LASTEXITCODE." -ForegroundColor Red
    exit 1
}

Write-Host "App installation completed successfully." -ForegroundColor Green
Write-Host "AIB customization step finished." -ForegroundColor Green
