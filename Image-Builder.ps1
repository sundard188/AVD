# =====================================================
# AIB Bootstrapper – Hybrid Model (MI + RBAC)
# Downloads artifacts only
# =====================================================

$ErrorActionPreference = "Stop"

$StorageAccount = "azuremarketplacetesting"
$Container      = "image"

$ZipName        = "software.zip"
$InstallerName  = "02-App-Install-FINAL.ps1"

$BaseUri        = "https://$StorageAccount.blob.core.windows.net/$Container"
$ZipUri         = "$BaseUri/$ZipName"
$InstallerUri   = "$BaseUri/$InstallerName"

$TempRoot       = "C:\Temp"
$SoftwareDir    = "C:\Temp\Software"
$ZipPath        = Join-Path $TempRoot $ZipName
$InstallerPath  = Join-Path $TempRoot $InstallerName

New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
Start-Transcript -Path "$TempRoot\bootstrapper.log" -Force

Write-Host "=== AIB Bootstrapper (Hybrid Mode) ==="

# ---------------- IMDS check ----------------
Write-Host "Checking IMDS..."
Invoke-RestMethod `
    -Uri "http://169.254.169.254/metadata/instance?api-version=2021-02-01" `
    -Headers @{ Metadata = "true" } `
    -TimeoutSec 5 | Out-Null

# ---------------- Token ----------------
Write-Host "Requesting MI token..."
$resource = [uri]::EscapeDataString("https://storage.azure.com/")
$tokenUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=$resource"

$token = (Invoke-RestMethod `
    -Uri $tokenUri `
    -Headers @{ Metadata = "true" }).access_token

if (-not $token) { throw "Failed to acquire token" }

$headers = @{
    Authorization  = "Bearer $token"
    "x-ms-version" = "2021-08-06"
}

# ---------------- Download ZIP ----------------
Write-Host "Downloading software.zip"
Invoke-WebRequest `
    -Uri $ZipUri `
    -Headers $headers `
    -OutFile $ZipPath `
    -TimeoutSec 120

if (-not (Test-Path $ZipPath)) { throw "software.zip missing" }

# ---------------- Extract ----------------
Write-Host "Extracting software.zip"
New-Item -ItemType Directory -Path $SoftwareDir -Force | Out-Null
Expand-Archive -Path $ZipPath -DestinationPath $SoftwareDir -Force

# ---------------- Download App Script ----------------
Write-Host "Downloading App-Final script"
Invoke-WebRequest `
    -Uri $InstallerUri `
    -Headers $headers `
    -OutFile $InstallerPath `
    -TimeoutSec 60

if (-not (Test-Path $InstallerPath)) { throw "Installer script missing" }

# ---------------- Execute ----------------
Write-Host "Executing App-Final.ps1"
& $InstallerPath

Write-Host "Bootstrapper completed"
Stop-Transcript
exit 0
