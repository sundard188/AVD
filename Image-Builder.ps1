# =====================================================
# AIB Bootstrapper – Public GitHub (RAW) – PRODUCTION
# =====================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------- Configuration ----------------
$ScriptUri  = "https://raw.githubusercontent.com/sundard188/AVD/main/Image-Builder.ps1"
$TempPath   = "C:\AIB"
$ScriptPath = Join-Path $TempPath "Image-Builder.ps1"

Write-Host "=============================================="
Write-Host "AIB Bootstrapper – Public GitHub RAW"
Write-Host "=============================================="

# ---------------- Prep ----------------
if (-not (Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
}

# ---------------- Download ----------------
Write-Host "Downloading script from public GitHub RAW..."
Write-Host "URI: $ScriptUri"

try {
    Invoke-WebRequest `
        -Uri $ScriptUri `
        -OutFile $ScriptPath `
        -UseBasicParsing
}
catch {
    throw "GitHub RAW download failed: $($_.Exception.Message)"
}

# ---------------- Validate ----------------
if (-not (Test-Path $ScriptPath)) {
    throw "Downloaded script not found at $ScriptPath"
}

$fileSize = (Get-Item $ScriptPath).Length
if ($fileSize -lt 512) {
    Write-Host "Downloaded content (diagnostic):"
    Get-Content $ScriptPath | Write-Host
    throw "Downloaded file too small ($fileSize bytes). Likely HTML or error page."
}

Write-Host "Download validated ($fileSize bytes)."

# ---------------- Execute (HARD FAIL MODE) ----------------
Write-Host "Executing Image-Builder script..."

$command = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
& '$ScriptPath'
"@

powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -Command $command

if ($LASTEXITCODE -ne 0) {
    throw "Image-Builder.ps1 exited with code $LASTEXITCODE"
}

Write-Host "Bootstrapper completed successfully."
