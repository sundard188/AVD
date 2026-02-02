# =====================================================
# AIB Template Deployment - GitHub Bootstrap Approach
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

# Step 1 — Verify managed identity + RBAC
Write-Host "[1/4] Verifying managed identity permissions..." -ForegroundColor Yellow

$identity = Get-AzUserAssignedIdentity -ResourceGroupName $resourceGroup -Name $identityName -ErrorAction SilentlyContinue
if (-not $identity) {
    Write-Host "ERROR: Managed identity '$identityName' not found." -ForegroundColor Red
    exit 1
}

$storage = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount

Write-Host "      Identity: $identityName" -ForegroundColor Gray
Write-Host "      Principal ID: $($identity.PrincipalId)" -ForegroundColor Gray

$roleAssignment = Get-AzRoleAssignment `
    -ObjectId $identity.PrincipalId `
    -RoleDefinitionName "Storage Blob Data Reader" `
    -Scope $storage.Id `
    -ErrorAction SilentlyContinue

if (-not $roleAssignment) {
    Write-Host "      Granting Storage Blob Data Reader role..." -ForegroundColor Yellow
    New-AzRoleAssignment `
        -ObjectId $identity.PrincipalId `
        -RoleDefinitionName "Storage Blob Data Reader" `
        -Scope $storage.Id | Out-Null

    Write-Host "      Waiting for RBAC propagation (5 min)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 300
}
else {
    Write-Host "      RBAC already assigned" -ForegroundColor Green
}

# Step 2 — Upload script to blob
Write-Host "[2/4] Uploading app installation script..." -ForegroundColor Yellow

if (-not (Test-Path ".\$appScriptName")) {
    Write-Host "ERROR: $appScriptName not found." -ForegroundColor Red
    exit 1
}

$ctx = $storage.Context

# Ensure container exists
$containerRef = Get-AzStorageContainer -Name $container -Context $ctx -ErrorAction SilentlyContinue
if (-not $containerRef) {
    New-AzStorageContainer -Name $container -Context $ctx | Out-Null
    Write-Host "      Container created: $container" -ForegroundColor Green
}

Set-AzStorageBlobContent `
    -Container $container `
    -File ".\$appScriptName" `
    -Blob $appScriptName `
    -Context $ctx `
    -Force | Out-Null

Write-Host "      Upload complete" -ForegroundColor Green

# Step 3 — Deploy AIB template
Write-Host "[3/4] Deploying AIB template..." -ForegroundColor Yellow

$existing = Get-AzImageBuilderTemplate `
    -ResourceGroupName $resourceGroup `
    -Name $templateName `
    -ErrorAction SilentlyContinue

if ($existing) {
    Remove-AzImageBuilderTemplate `
        -ResourceGroupName $resourceGroup `
        -Name $templateName `
        -Force | Out-Null
}

New-AzResourceGroupDeployment `
    -ResourceGroupName $resourceGroup `
    -TemplateFile ".\aib-template-GITHUB-BOOTSTRAP.json" `
    -Verbose

Write-Host "      Template deployed" -ForegroundColor Green

# Step 4 — Start build
Write-Host "[4/4] Starting image build..." -ForegroundColor Yellow

Start-AzImageBuilderTemplate `
    -ResourceGroupName $resourceGroup `
    -Name $templateName `
    -NoWait

Write-Host "Build started." -ForegroundColor Green
