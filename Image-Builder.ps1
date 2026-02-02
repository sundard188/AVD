# =====================================================
# AIB Template Deployment - GitHub Bootstrap Approach
# =====================================================
# Uses GitHub-hosted bootstrap script that downloads
# the app installation script from blob storage using
# managed identity authentication
# =====================================================

$ErrorActionPreference = 'Stop'

# Configuration
$resourceGroup = "Test-Image-Builder"
$templateName = "AVD-Win11-AppInstall-Template"
$storageAccount = "azuremarketplacetesting"
$container = "image"
$identityName = "aibIdentity"
$appScriptName = "02-App-Install-FINAL.ps1"

Write-Host "=============================================="
Write-Host "AIB Deployment - GitHub Bootstrap Method"
Write-Host "=============================================="
Write-Host ""

# Step 1: Verify managed identity has Storage Blob Data Reader role
Write-Host "[1/4] Verifying managed identity permissions..." -ForegroundColor Yellow
$identity = Get-AzUserAssignedIdentity -ResourceGroupName $resourceGroup -Name $identityName
$storage = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount

Write-Host "      Identity: $identityName" -ForegroundColor Gray
Write-Host "      Principal ID: $($identity.PrincipalId)" -ForegroundColor Gray

$roleAssignment = Get-AzRoleAssignment `
    -ObjectId $identity.PrincipalId `
    -RoleDefinitionName "Storage Blob Data Reader" `
    -Scope $storage.Id `
    -ErrorAction SilentlyContinue

if ($roleAssignment) {
    Write-Host "      Storage Blob Data Reader role is assigned" -ForegroundColor Green
    Write-Host "      Assigned on: $($roleAssignment.CreatedOn)" -ForegroundColor Gray
} else {
    Write-Host "      ⚠ Granting Storage Blob Data Reader role..." -ForegroundColor Yellow
    New-AzRoleAssignment `
        -ObjectId $identity.PrincipalId `
        -RoleDefinitionName "Storage Blob Data Reader" `
        -Scope $storage.Id | Out-Null
    Write-Host "      Role assigned. Waiting 90 seconds for RBAC propagation..." -ForegroundColor Green
    Start-Sleep -Seconds 90
}

# Step 2: Upload app installation script to blob storage
Write-Host "[2/4] Uploading app installation script to blob storage..." -ForegroundColor Yellow

if (-not (Test-Path ".\$appScriptName")) {
    Write-Host "      ERROR: $appScriptName not found in current directory" -ForegroundColor Red
    Write-Host "      Please ensure the file is in the same directory as this script" -ForegroundColor Red
    exit 1
}

$ctx = $storage.Context
Set-AzStorageBlobContent `
    -Container $container `
    -File ".\$appScriptName" `
    -Blob $appScriptName `
    -Context $ctx `
    -Force | Out-Null

$blob = Get-AzStorageBlob -Container $container -Blob $appScriptName -Context $ctx
$sizeKB = [math]::Round($blob.Length / 1KB, 2)
Write-Host "      Uploaded: $sizeKB KB" -ForegroundColor Green
Write-Host "      Last Modified: $($blob.LastModified)" -ForegroundColor Gray
Write-Host "      Blob URL: $($blob.ICloudBlob.Uri.AbsoluteUri)" -ForegroundColor Gray

# Step 3: Deploy AIB template
Write-Host "[3/4] Deploying AIB template..." -ForegroundColor Yellow

# Check if template exists
$existing = Get-AzImageBuilderTemplate `
    -ResourceGroupName $resourceGroup `
    -Name $templateName `
    -ErrorAction SilentlyContinue

if ($existing) {
    Write-Host "      Removing existing template..." -ForegroundColor Yellow
    Remove-AzImageBuilderTemplate `
        -ResourceGroupName $resourceGroup `
        -Name $templateName `
        -Force | Out-Null
    Write-Host "      Existing template removed" -ForegroundColor Green
}

Write-Host "      Deploying new template..." -ForegroundColor Yellow
New-AzResourceGroupDeployment `
    -ResourceGroupName $resourceGroup `
    -TemplateFile ".\aib-template-GITHUB-BOOTSTRAP.json" `
    -Verbose

Write-Host "      Template deployed successfully" -ForegroundColor Green

# Step 4: Start image build
Write-Host "[4/4] Starting image build..." -ForegroundColor Yellow
Start-AzImageBuilderTemplate `
    -ResourceGroupName $resourceGroup `
    -Name $templateName `
    -NoWait

Write-Host "      Build started" -ForegroundColor Green

Write-Host ""
Write-Host "=============================================="
Write-Host "Deployment Complete!"
Write-Host "=============================================="
Write-Host ""
Write-Host "Build Process:" -ForegroundColor Cyan
Write-Host "  1. GitHub script downloads from: https://raw.githubusercontent.com/sundard188/AVD/refs/heads/main/Image-Builder.ps1" -ForegroundColor Gray
Write-Host "  2. GitHub script uses managed identity to authenticate" -ForegroundColor Gray
Write-Host "  3. GitHub script downloads: $appScriptName from blob storage" -ForegroundColor Gray
Write-Host "  4. GitHub script executes: $appScriptName" -ForegroundColor Gray
Write-Host ""
Write-Host "Expected Duration: ~70 minutes" -ForegroundColor Yellow
Write-Host ""
Write-Host "Monitor Progress:" -ForegroundColor Cyan
Write-Host "  Get-AzImageBuilderTemplate -ResourceGroupName '$resourceGroup' -Name '$templateName' | Select Name, LastRunStatus*" -ForegroundColor White
Write-Host ""
Write-Host "Check Detailed Status:" -ForegroundColor Cyan
Write-Host "  `$status = Get-AzImageBuilderTemplate -ResourceGroupName '$resourceGroup' -Name '$templateName'" -ForegroundColor White
Write-Host "  `$status.LastRunStatus" -ForegroundColor White
Write-Host ""
Write-Host "View Last Build Message:" -ForegroundColor Cyan
Write-Host "  `$status.LastRunStatusMessage" -ForegroundColor White
Write-Host ""
