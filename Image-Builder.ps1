######################
#   Configuration    #
######################
$StorageAccountName = "azuremarketplacetesting"
$ContainerName = "image"
$InstallScriptName = "02-App-Install-FINAL.ps1"  # ← UPDATED to match your blob
$TempDir = "C:\Temp"
$LogFile = Join-Path $TempDir "bootstrap-appinstall.log"

# Create working directory
if (!(Test-Path $TempDir)) {   
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

# Simple logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "$timestamp [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage
    Write-Host $logMessage
}

#######################################
#    GET MANAGED IDENTITY TOKEN       #
#######################################
Write-Log "============================================="
Write-Log "AVD Application Installation Bootstrap - Starting"
Write-Log "============================================="
Write-Log "Storage Account: $StorageAccountName"
Write-Log "Container: $ContainerName"
Write-Log "Script to download: $InstallScriptName"

Write-Log "Obtaining managed identity token..."
try {
    $response = Invoke-RestMethod `
        -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-01-01&resource=https://storage.azure.com/" `
        -Headers @{"Metadata"="true"} `
        -Method Get `
        -ErrorAction Stop
    
    $token = $response.access_token
    $headers = @{
        "Authorization" = "Bearer $token"
        "x-ms-version" = "2021-08-06"
    }
    Write-Log "Successfully obtained authentication token" "SUCCESS"
} 
catch {
    Write-Log "Failed to obtain managed identity token: $($_.Exception.Message)" "ERROR"
    Write-Log "Ensure the VM has a managed identity with 'Storage Blob Data Reader' role" "ERROR"
    
    # Add diagnostic info
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Log "HTTP Status: $statusCode" "ERROR"
    }
    
    exit 1
}

#######################################
#    DOWNLOAD INSTALLATION SCRIPT     #
#######################################
$scriptPath = Join-Path $TempDir $InstallScriptName
$blobUrl = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$InstallScriptName"

Write-Log "Downloading installation script from private blob storage..."
Write-Log "URL: $blobUrl"

try {
    Invoke-RestMethod `
        -Uri $blobUrl `
        -Headers $headers `
        -OutFile $scriptPath `
        -ErrorAction Stop
    
    if (Test-Path $scriptPath) {
        $sizeKB = [math]::Round((Get-Item $scriptPath).Length / 1KB, 2)
        Write-Log "Downloaded successfully ($sizeKB KB)" "SUCCESS"
    }
    else {
        Write-Log "Download completed but file not found at $scriptPath" "ERROR"
        exit 1
    }
}
catch {
    $errorMsg = "Failed to download installation script: $($_.Exception.Message)"
    
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorMsg += " (HTTP $statusCode)"
        
        if ($statusCode -eq 403) {
            $errorMsg += " - Verify RBAC 'Storage Blob Data Reader' role assignment"
        }
        elseif ($statusCode -eq 404) {
            $errorMsg += " - Verify blob path: $ContainerName/$InstallScriptName"
        }
    }
    
    Write-Log $errorMsg "ERROR"
    exit 1
}

#######################################
#    EXECUTE INSTALLATION SCRIPT      #
#######################################
Write-Log "Executing installation script..."
Write-Log "Script path: $scriptPath"

try {
    # FIXED: Use explicit powershell.exe call with Bypass policy
    $process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`"" `
        -Wait `
        -PassThru `
        -NoNewWindow
    
    $exitCode = $process.ExitCode
    
    if ($exitCode -eq 0 -or $null -eq $exitCode) {
        Write-Log "Installation script completed successfully" "SUCCESS"
    }
    else {
        Write-Log "Installation script exited with code: $exitCode" "WARNING"
    }
}
catch {
    Write-Log "Error executing installation script: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}

Write-Log "============================================="
Write-Log "Bootstrap completed"
Write-Log "============================================="
