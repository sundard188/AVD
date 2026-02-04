# =====================================================
# AIB Bootstrapper – FINAL (GitHub → MI → Blob)
# =====================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TranscriptPath = $null

try {
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
    Start-Transcript -Path $TranscriptPath -Append -Force

    Write-Host "=============================================="
    Write-Host "AIB Bootstrapper – Managed Identity Mode"
    Write-Host "=============================================="

    # ---------------- Acquire Managed Identity Token ----------------
    Write-Host "Requesting Managed Identity token from IMDS..."

    $imdsUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://storage.azure.com/"

    $tokenResponse = Invoke-RestMethod `
        -Uri $imdsUri `
        -Headers @{ Metadata = "true" } `
        -Method GET

    $accessToken = $tokenResponse.access_token

    if (-not $accessToken) {
        throw "Managed Identity token acquisition failed"
    }

    Write-Host "Managed Identity token acquired."

    # ---------------- Download Installer from Blob ----------------
    Write-Host "Downloading installer from private Blob..."
    Write-Host ("URI: {0}" -f $InstallerUri)

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
        throw ("Installer not found at {0}" -f $InstallerPath)
    }

    $fileSize = (Get-Item $InstallerPath).Length
    if ($fileSize -lt 1024) {
        Write-Host "Downloaded content (diagnostic):"
        Get-Content $InstallerPath | Write-Host
        throw ("Installer file too small ({0} bytes). Download failed." -f $fileSize)
    }

    Write-Host ("Installer downloaded successfully ({0} bytes)." -f $fileSize)

    # ---------------- Execute Installer ----------------
    Write-Host "Executing installer script..."

    powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $InstallerPath

    if ($LASTEXITCODE -ne 0) {
        throw ("Installer exited with code {0}" -f $LASTEXITCODE)
    }

    Write-Host "Installer completed successfully."
    Write-Host "Bootstrapper completed successfully."

    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Error "BOOTSTRAPPER FAILED"
    Write-Error ("Error: {0}" -f $_.Exception.Message)
    Write-Error ("Stack Trace: {0}" -f $_.ScriptStackTrace)

    if ($TranscriptPath) {
        Stop-Transcript | Out-Null
    }
    exit 1
}
