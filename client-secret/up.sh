#!/bin/bash
# Used to bootstrap infrastructure required by Terraform

set -e  # Exit on error
set -o pipefail  # Exit on pipeline failure

# Check for jq installation
if ! command -v jq >/dev/null; then
    echo "Error: jq is not installed."
    exit 1
fi

# Central error handling
error_handler() {
    echo "Error on line $1"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Check and export subscription/tenant if needed
if [[ -z "$subscriptionId" ]]; then
    export subscriptionId=$(az account show --query id -o tsv)
    [[ -n "$subscriptionId" ]] && echo "Subscription exported..." || exit 1
else
    echo "Subscription details are set..."
fi

if [[ -z "$tenantId" ]]; then
    export tenantId=$(az account show --query homeTenantId -o tsv)
    [[ -n "$tenantId" ]] && echo "Tenant exported..." || exit 1
else
    echo "Tenant details are set..."
fi

# Sources variables
if [[ -f ".env" ]]; then
    source .env
fi

# Set subscription
az account set --subscription "$subscriptionId"

# Creates resource group
az group create --name "$rg" \
    --location "$location" \
    --tags environment="$tag" \
    --subscription "$subscriptionId"
echo "Resources group created..."

# RBAC Condition to prevent assignment of privileged roles
# Excludes: Owner, User Access Administrator, Role Based Access Control Administrator,
# Privileged Role Administrator, Contributor, Managed Identity Contributor, Privileged Authentication Administrator
export RBAC_CONDITION="(
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
)"

# create service principal if not exists already
if [[ $(az ad sp list --display-name $spName --query "[].displayName" -o tsv) = "$spName" ]]; then
    echo "Service principal already exists..."
    export spId=$(az ad sp list --display-name $spName --query "[].appId" -o tsv)
else
    # Create service principal without initial role assignment
    export sp=$(az ad sp create-for-rbac \
        --name "$spName" \
        --years 99)
    echo "Service principal created..."
    # Set service principal id and secret variables
    export spSecret=$(echo "$sp" | jq -r '.password')
    export spId=$(echo "$sp" | jq -r '.appId')
    
    # Assign Contributor role for resource management
    if ! az role assignment create \
        --assignee "$spId" \
        --scope "/subscriptions/$subscriptionId" \
        --role "Contributor"; then
        echo "Error: Failed to assign Contributor role"
        exit 1
    fi
    echo "Contributor role assigned..."
    
    # Assign Role Based Access Control Administrator with condition
    if ! az role assignment create \
        --assignee "$spId" \
        --scope "/subscriptions/$subscriptionId" \
        --role "Role Based Access Control Administrator" \
        --condition "$RBAC_CONDITION" \
        --condition-version "2.0"; then
        echo "Error: Failed to assign Role Based Access Control Administrator role"
        exit 1
    fi
    echo "Role Based Access Control Administrator role assigned with condition..."
fi

# Add Entra ID API permissions - Group.ReadWrite.All, GroupMember.ReadWrite.All, User.Read.All
az ad app permission add \
    --id "$spId" \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions \
    62a82d76-70ea-41e2-9197-370581804d09=Role \
    dbaae8cf-10b5-4b86-a4a1-f871c94c6695=Role \
    df021288-bdef-4463-88db-98f22de89214=Role 
echo "Service principal authorized..."

# Update roles
az role assignment create \
    --assignee "$spId" \
    --scope "/subscriptions/$subscriptionId" \
    --role "Monitoring Metrics Publisher"
echo "Service principal role updated..."

# Get local user
export userId=$(az ad signed-in-user show --query id -o tsv)
echo "Local user fetched..."

# Creates resources
az deployment group create \
    --name "$name" \
    --resource-group "$rg" \
    --template-file ./resources.bicep \
    --subscription "$subscriptionId" \
    --mode Incremental \
    --parameters "vault_name=$vaultName" \
                 "vault_sku=$vaultSku" \
                 "sa_name=$saName" \
                 "sa_sku=$saSku" \
                 "sc_name=$scName" \
                 "tenant_id=$tenantId" \
                 "user_id=$userId" \
                 "tag=$tag" \
                 "location=$location"
echo "Deployment created..."

# Gets storage account key
export saKey=$(az storage account keys list \
    --subscription="$subscriptionId" \
    --resource-group "$rg" \
    --account-name "$saName" \
    --query '[0].value' -o tsv)
echo "Storage container created..."

# Saves storage account details to vault
az keyvault secret set --vault-name "$vaultName" \
    --name "sa-key" \
    --value "$saKey"
az keyvault secret set --vault-name "$vaultName" \
    --name "sa-name" \
    --value "$saName"
az keyvault secret set --vault-name "$vaultName" \
    --name "sc-name" \
    --value "$scName"
echo "Secrets are saved in vault..."

# Save service principal details to vault
az keyvault secret set --vault-name "$vaultName" \
    --name "sp-id" \
    --value "$spId"

# Save subscription id to vault
az keyvault secret set --vault-name "$vaultName" \
    --name "subscription-id" \
    --value "$subscriptionId"

# checks if a password secret already exists and only sets secret value if password doesn't exist
if [  -n "$(az keyvault secret list --vault-name "$vaultName"  --query "[].name" | grep "sp-secret")" ]
then
  echo "SP secret already exists..."
elif [ -z "$spSecret" ]; then
  echo "spSecret is not set. Please enter the value:"
  read spSecret
  az keyvault secret set --vault-name "$vaultName" \
    --name "sp-secret" \
    --value "$spSecret"
  echo "Secrets are saved in vault..."
elif [ -n "$spSecret" ]; then
  az keyvault secret set --vault-name "$vaultName" \
    --name "sp-secret" \
    --value "$spSecret"
  echo "Secrets are saved in vault..."
fi

# Add vault access
az role assignment create \
    --assignee "$spId" \
    --role "Key Vault Secrets Officer" \
    --scope "/subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.KeyVault/vaults/$vaultName"
echo "Role for Service Principal set"

# Map Partner ID (optional)
echo "---"
read -r -p "Do you like to map our Partner ID? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    az extension add --name managementpartner --upgrade --yes
    az login --tenant "$tenantId" --service-principal -u "$spId" -p "$spSecret"
    az managementpartner create --partner-id 3699617
    az logout
    AZURE_CORE_LOGIN_EXPERIENCE_V2=off az login --tenant "$tenantId"
    az account set --subscription "$subscriptionId"
fi
