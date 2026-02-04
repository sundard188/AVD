# =====================================================
# AIB Bootstrapper – FINAL AIB-SAFE (GitHub → MI → Blob)
# =====================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TranscriptPath = $null

try {
    # ---------------- Configuration ----------------
    $StorageAccount = "azuremarketplacetesting"
    $Container      = "image"
    $InstallerName  = "02-App-Install-FINAL.ps1"

    $TempPath       = "C:\AIB"
    $InstallerPath  = Join-Path $TempPath $InstallerName
    $InstallerUri   = "https://$StorageAccount.blob.core.windows.net/$Container/$InstallerName"

    # ---------------- Prep ----------------
    if (-not (Test-Path $TempPath)) {
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
    }

    $TranscriptPath = Join-Path $TempPath "bootstrapper-transcript.log"
    Start-Transcript -Path $TranscriptPath -Append -Force

    Write-Host "=============================================="
    Write-Host "AIB Bootstrapper - Managed Identity Mode"
    Write-Host "=============================================="

    # ---------------- Managed Identity Token ----------------
    Write-Host "Requesting Managed Identity token"

    $amp = [char]38
    $imdsBase = "http://169.254.169.254/metadata/identity/oauth2/token"
    $imdsQuery = "api-version=2021-02-01${amp}resource=https://storage.azure.com/"
    $imdsUri = "$imdsBase?$imdsQuery"

    $tokenResponse = Invoke-RestMethod `
        -Uri $imdsUri `
        -Headers @{ Metadata = "true" } `
        -Method GET

    $accessToken = $tokenResponse.access_token

    if (-not $accessToken) {
        throw "Managed Identity token acquisition failed"
    }

    Write-Host "Managed Identity token acquired"

    # ---------------- Download Installer ----------------
    Write-Host "Downloading installer from private Blob"

    $headers = @{
        Authorization  = "Bearer $accessToken"
        "x-ms-version" = "2021-08-06"
    }

    Invoke-WebRequest `
        -Uri $InstallerUri `
        -Headers $headers `
        -OutFile $InstallerPath `
        -UseBasicParsing `
        -TimeoutSec 120

    # ---------------- Validate Download ----------------
    if (-not (Test-Path $InstallerPath)) {
        throw "Installer file missing after download"
    }

    $fileSize = (Get-Item $InstallerPath).Length

    if ($fileSize -lt 1024) {
        Write-Host "Installer content diagnostic output"
        Get-Content $InstallerPath | Write-Host
        throw ("Installer file too small. Size = {0} bytes" -f $fileSize)
    }

    Write-Host ("Installer download successful. Size = {0} bytes" -f $fileSize)

    # ---------------- Execute Installer ----------------
    Write-Host "Executing installer script"

    powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $InstallerPath

    if ($LASTEXITCODE -ne 0) {
        throw ("Installer execution failed. Exit code = {0}" -f $LASTEXITCODE)
    }

    Write-Host "Installer completed successfully"
    Write-Host "Bootstrapper completed successfully"

    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Error "BOOTSTRAPPER FAILED"
    Write-Error ("Error message: {0}" -f $_.Exception.Message)
    Write-Error ("Script stack trace: {0}" -f $_.ScriptStackTrace)

    if ($TranscriptPath) {
        Stop-Transcript | Out-Null
    }
    exit 1
}
