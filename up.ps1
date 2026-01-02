[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $subscriptionId = $env:subscriptionId,

    [Parameter()]
    [string]
    $tenantId = $env:tenantId
)

# Error trapping
trap {
    Write-Host "Error on line $($($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)"
    exit 1
}

# If $subscriptionId is not set, try to set it using the az CLI
# If $subscriptionId is still not set after that, throw an error
if (-not $subscriptionId) {
    $subscriptionId = az account show --query id -o tsv
    if (-not $subscriptionId) {
        throw "Failed to obtain subscription ID"
    }
}
Write-Host "Subscription ID set to $subscriptionId"

# If $tenantId is not set, try to set it using the az CLI
# If $tenantId is still not set after that, throw an error
if (-not $tenantId) {
    $tenantId = az account show --query homeTenantId -o tsv
    if (-not $tenantId) {
        throw "Failed to obtain tenant ID"
    }
}
Write-Host "Tenant ID set to $tenantId"

# Load independent variables from .env.powershell file
$envVars = Get-Content .env.powershell | Out-String | ConvertFrom-StringData

# Declare dependent variables
$spName = "sp-$($envVars['name'])-$($envVars['suffix'])"
$rg = "rg-$($envVars['name'])-$($envVars['suffix'])"
$tag = $envVars['suffix']
$saName = "stac0$($envVars['name'])0$($envVars['suffix'])"
$scName = "blob0$($envVars['name'])0$($envVars['suffix'])"
$vaultName = "akv-$($envVars['name'])-$($envVars['suffix'])"

# Set subscription
az account set --subscription "$subscriptionId"

# Creates resource group
az group create `
    --name $rg `
    --location "$($envVars['location'])" `
    --tags environment="$tag" `
    --subscription "$subscriptionId"
if (-not $?) {
    throw "Failed to create resource group"
}
Write-Host "Resource group created..."

# RBAC Condition to prevent assignment of privileged roles
# Excludes: Owner, User Access Administrator, Role Based Access Control Administrator,
# Privileged Role Administrator, Contributor, Managed Identity Contributor, Privileged Authentication Administrator
$rbacCondition = @"
(
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
 )
 OR 
 (
  @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168, a8889054-8d42-49c9-bc1c-52486c10e7cd, b24988ac-6180-42a0-ab88-20f7382dd24c, 76cc9ee4-d5d3-4a45-a930-26add3d73475, 32e6a4ec-6095-4e37-b54b-12aa350ba81f}
 )
)
AND
(
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
 )
 OR 
 (
  @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168, a8889054-8d42-49c9-bc1c-52486c10e7cd, b24988ac-6180-42a0-ab88-20f7382dd24c, 76cc9ee4-d5d3-4a45-a930-26add3d73475, 32e6a4ec-6095-4e37-b54b-12aa350ba81f}
 )
)
"@

# Creates a service principal if it doesn't exist
$sp = az ad sp list --display-name $spName --query "[].displayName" -o tsv
if ($sp -eq $spName) {
    Write-Host "Service principal already exists..."
    $spId = az ad sp list --display-name $spName --query "[].appId" -o tsv
}
else {
    # Create service principal without initial role assignment
    $sp = az ad sp create-for-rbac `
        --name $spName `
        --years 99 | ConvertFrom-Json
    Write-Host "Service principal created..."
    # Set service principal id and secret variables
    $spSecret = $sp.password
    $spId = $sp.appId
    
    # Assign Contributor role for resource management
    az role assignment create `
        --assignee "$spId" `
        --scope "/subscriptions/$subscriptionId" `
        --role "Contributor"
    if (-not $?) {
        throw "Failed to assign Contributor role"
    }
    Write-Host "Contributor role assigned..."
    
    # Assign Role Based Access Control Administrator with condition
    az role assignment create `
        --assignee "$spId" `
        --scope "/subscriptions/$subscriptionId" `
        --role "Role Based Access Control Administrator" `
        --condition $rbacCondition `
        --condition-version "2.0"
    if (-not $?) {
        throw "Failed to assign Role Based Access Control Administrator role"
    }
    Write-Host "Role Based Access Control Administrator role assigned with condition..."
}

# Add AD API permissions - Group.ReadWrite.All, GroupMember.ReadWrite.All, User.Read.All
az ad app permission add `
    --id "$spId" `
    --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions `
    62a82d76-70ea-41e2-9197-370581804d09=Role `
    dbaae8cf-10b5-4b86-a4a1-f871c94c6695=Role `
    df021288-bdef-4463-88db-98f22de89214=Role
if (-not $?) {
    throw "Failed to add ADD API permissions"
}
Write-Host "ADD API permissions added..."

# Update roles
az role assignment create `
    --assignee "$spId" `
    --scope "/subscriptions/$subscriptionId" `
    --role "Monitoring Metrics Publisher"
if (-not $?) {
    throw "Failed to update roles"
}
Write-Host "Roles updated..."

# Get local user
$userId = az ad signed-in-user show --query id -o tsv
if (-not $?) {
    throw "Failed to get local user"
}
Write-Host "Local user fetched..."

# Creates resources
az deployment group create `
    --name "$($envVars['name'])" `
    --resource-group "$rg" `
    --template-file ./resources.bicep `
    --subscription "$subscriptionId" `
    --mode Incremental `
    --parameters `
    vault_name="$vaultName" `
    vault_sku="$($envVars['vaultSku'])" `
    sa_name="$saName" `
    sa_sku="$($envVars['saSku'])" `
    sc_name="$scName" `
    tenant_id="$tenantId" `
    user_id="$userId" `
    tag="$tag" `
    location="$($envVars['location'])"
if (-not $?) {
    throw "Failed to create deployment"
}
Write-Host "Deployment created..."

# Gets storage account key
$saKey = az storage account keys list `
    --subscription="$subscriptionId" `
    --resource-group "$rg" `
    --account-name "$saName" `
    --query [0].value `
    -o tsv
if (-not $?) {
    throw "Failed to get storage account key"
}
Write-Host "Storage account key fetched..."

# Save storage account details to vault
az keyvault secret set --vault-name "$vaultName" `
    --name "sa-key" `
    --value "$saKey"
az keyvault secret set --vault-name "$vaultName" `
    --name "sa-name" `
    --value "$saName"
az keyvault secret set --vault-name "$vaultName" `
    --name "sc-name" `
    --value "$scName"
if (-not $?) {
    throw "Failed to save storage account details to vault"
}
Write-Host "Storage account details saved to vault..."

# Save service principal details to vault
az keyvault secret set --vault-name "$vaultName" `
    --name "sp-id" `
    --value "$spId"

# Save subscription id to vault
az keyvault secret set --vault-name "$vaultName" `
    --name "subscription-id" `
    --value "$subscriptionId"

# Check if secret already exists and if not, set it
$secretList = az keyvault secret list --vault-name $vaultName --query "[].name" -o tsv
if ($secretList -match "sp-secret") {
    Write-Host "SP secret already exists..."
}
elseif ([string]::IsNullOrEmpty($spSecret)) {
    Write-Host "spSecret is not set. Please enter the value:"
    $spSecret = Read-Host
    az keyvault secret set --vault-name $vaultName `
        --name "sp-secret" `
        --value $spSecret
    Write-Host "Secrets are saved in vault..."
}
else {
    az keyvault secret set --vault-name $vaultName `
        --name "sp-secret" `
        --value $spSecret
    Write-Host "Secrets are saved in vault..."
}
Write-Host "Service principal details saved to vault..."

# Add vault access
az role assignment create `
    --assignee "$spId" `
    --role "Key Vault Secrets Officer" `
    --scope "/subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.KeyVault/vaults/$vaultName"
if (-not $?) {
    throw "Failed to create role assignment"
}
Write-Host "Role assignment created"

# Map Partner ID (optional)
Write-Host "---"
$response = Read-Host "Do you like to map our Partner ID? [y/N]"
if ($response -imatch "^(y|yes)$") {
    az extension add --name managementpartner
    az login --tenant "$tenantId" --service-principal -u "$spId" -p "$spSecret"
    az managementpartner create --partner-id 3699617
    az logout
    Write-Host "---"
    Write-Host "Please login."
    az login
}
