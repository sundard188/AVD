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
# This VM has a managed identity.  IMDS is the only way
# to get a credential inside an AIB VM without installing
# Az modules or hard-coding keys.
#
# The token is scoped to storage.azure.com — it is only
# valid for Blob/Table/Queue/File storage endpoints.
Write-Host "Requesting OAuth2 token from IMDS..." -ForegroundColor Yellow

$imdsUri  = "http://169.254.169.254/metadata/identity/oauth2/token" +
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
# Container is private (no anonymous access).
# The Bearer token satisfies the auth requirement.
# x-ms-version tells Blob Storage which API behaviour to use.
Write-Host "Downloading app install script from blob..." -ForegroundColor Yellow
Write-Host "URI: $BlobUri" -ForegroundColor Gray

$blobHeaders = @{
    "Authorization" = "Bearer $bearerToken"
    "x-ms-version"  = "2021-08-06"
}

Invoke-WebRequest `
    -Uri     $BlobUri `
    -Headers $blobHeaders `
    -OutFile $ScriptPath `
    -UseBasicParsing

# -------- Verify the download is a real file, not an error page --------
# Invoke-WebRequest writes the response body regardless of status code.
# On a 401/403 that body is an XML error page — Test-Path would still
# return True.  Check that the file is at least non-trivial in size.
if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERROR: Script file not found at $ScriptPath." -ForegroundColor Red
    exit 1
}

$fileSize = (Get-Item $ScriptPath).Length
if ($fileSize -lt 100) {
    Write-Host "ERROR: Downloaded file is $fileSize bytes — likely an auth error page, not the script." -ForegroundColor Red
    Write-Host "       Contents:" -ForegroundColor Red
    Get-Content $ScriptPath | Write-Host
    exit 1
}

Write-Host "Download successful ($($fileSize) bytes)." -ForegroundColor Green

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
