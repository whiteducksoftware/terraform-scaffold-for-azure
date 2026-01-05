#!/bin/bash
set -e

#######################################
# Terraform Scaffold for Azure
# OIDC Authentication Setup
# Supports both GitHub Actions and Azure DevOps
#######################################

#######################################
# CONFIGURATION - Edit before running
#######################################
# Choose the federated credential file:
# - "federated_credential_github.json" for GitHub Actions
# - "federated_credential_ado.json" for Azure DevOps
FEDERATED_CREDENTIAL_FILE="federated_credential_github.json"

#######################################
# Load environment variables
#######################################
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: .env file not found"
    exit 1
fi

#######################################
# Set subscription ID
#######################################
if [ -z "$subscriptionId" ]; then
    subscriptionId=$(az account show --query id -o tsv)
    if [ -z "$subscriptionId" ]; then
        echo "Failed to obtain subscription ID"
        exit 1
    fi
fi
echo "Subscription ID set to $subscriptionId"

#######################################
# Set tenant ID
#######################################
if [ -z "$tenantId" ]; then
    tenantId=$(az account show --query homeTenantId -o tsv)
    if [ -z "$tenantId" ]; then
        echo "Failed to obtain tenant ID"
        exit 1
    fi
fi
echo "Tenant ID set to $tenantId"

#######################################
# Declare dependent variables
#######################################
spName="sp-${name}-${suffix}"
rg="rg-${name}-${suffix}"
tag="${suffix}"
saName="stac0${name}0${suffix}"
scName="blob0${name}0${suffix}"

#######################################
# Set subscription
#######################################
az account set --subscription "$subscriptionId"

#######################################
# Create resource group
#######################################
az group create \
    --name "$rg" \
    --location "$location" \
    --tags environment="$tag" \
    --subscription "$subscriptionId"
echo "Resource group created..."

#######################################
# RBAC Condition to prevent assignment of privileged roles
# Excludes: Owner, User Access Administrator, Role Based Access Control Administrator,
# Privileged Role Administrator, Contributor, Managed Identity Contributor, Privileged Authentication Administrator
#######################################
rbacCondition='(
 (
  !(ActionMatches{'"'"'Microsoft.Authorization/roleAssignments/write'"'"'})
 )
 OR 
 (
  @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168, a8889054-8d42-49c9-bc1c-52486c10e7cd, b24988ac-6180-42a0-ab88-20f7382dd24c, 76cc9ee4-d5d3-4a45-a930-26add3d73475, 32e6a4ec-6095-4e37-b54b-12aa350ba81f}
 )
)
AND
(
 (
  !(ActionMatches{'"'"'Microsoft.Authorization/roleAssignments/delete'"'"'})
 )
 OR 
 (
  @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168, a8889054-8d42-49c9-bc1c-52486c10e7cd, b24988ac-6180-42a0-ab88-20f7382dd24c, 76cc9ee4-d5d3-4a45-a930-26add3d73475, 32e6a4ec-6095-4e37-b54b-12aa350ba81f}
 )
)'

#######################################
# Create service principal if it doesn't exist
#######################################
sp=$(az ad sp list --display-name "$spName" --query "[].displayName" -o tsv)
if [ "$sp" = "$spName" ]; then
    echo "Service principal already exists..."
    spId=$(az ad sp list --display-name "$spName" --query "[].appId" -o tsv)
    appObjectId=$(az ad app show --id "$spId" --query "id" -o tsv)
else
    # Create service principal
    spOutput=$(az ad sp create-for-rbac \
        --name "$spName" \
        --years 99)
    echo "Service principal created..."
    
    # Set service principal id variable
    spId=$(echo "$spOutput" | jq -r '.appId')
    spSecret=$(echo "$spOutput" | jq -r '.password')
    
    # Get appObjectId
    appObjectId=$(az ad app show --id "$spId" --query "id" -o tsv)
    
    # Assign Contributor role for resource management
    az role assignment create \
        --assignee "$spId" \
        --scope "/subscriptions/$subscriptionId" \
        --role "Contributor"
    echo "Contributor role assigned..."
    
    # Assign Role Based Access Control Administrator with condition
    az role assignment create \
        --assignee "$spId" \
        --scope "/subscriptions/$subscriptionId" \
        --role "Role Based Access Control Administrator" \
        --condition "$rbacCondition" \
        --condition-version "2.0"
    echo "Role Based Access Control Administrator role assigned with condition..."
fi

#######################################
# Add Entra ID API permissions
# Group.ReadWrite.All, GroupMember.ReadWrite.All, User.Read.All
#######################################
az ad app permission add \
    --id "$spId" \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions \
    62a82d76-70ea-41e2-9197-370581804d09=Role \
    dbaae8cf-10b5-4b86-a4a1-f871c94c6695=Role \
    df021288-bdef-4463-88db-98f22de89214=Role
echo "Entra ID API permissions added..."

#######################################
# Assign Monitoring Metrics Publisher role
#######################################
az role assignment create \
    --assignee "$spId" \
    --scope "/subscriptions/$subscriptionId" \
    --role "Monitoring Metrics Publisher"
echo "Monitoring Metrics Publisher role assigned..."

#######################################
# Create federated credential
#######################################
az ad app federated-credential create \
    --id "$appObjectId" \
    --parameters "@./${FEDERATED_CREDENTIAL_FILE}"
echo "Federated credential created from ${FEDERATED_CREDENTIAL_FILE}..."

#######################################
# Get local user
#######################################
userId=$(az ad signed-in-user show --query id -o tsv)
echo "Local user fetched..."

#######################################
# Deploy resources
#######################################
az deployment group create \
    --name "$name" \
    --resource-group "$rg" \
    --template-file ./resources.bicep \
    --subscription "$subscriptionId" \
    --mode Incremental \
    --parameters \
    sa_name="$saName" \
    sa_sku="$saSku" \
    sc_name="$scName" \
    tag="$tag" \
    location="$location"
echo "Deployment created..."

#######################################
# Assign Storage Blob Data Owner role
#######################################
az role assignment create \
    --assignee "$spId" \
    --scope "/subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$saName" \
    --role "Storage Blob Data Owner"
echo "Storage Blob Data Owner role assigned..."

#######################################
# Map Partner ID (optional)
#######################################
echo "---"
read -p "Do you like to map our Partner ID? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    az extension add --name managementpartner --upgrade --yes
    az login --tenant "$tenantId" --service-principal -u "$spId" -p "$spSecret"
    az managementpartner create --partner-id 3699617
    az logout
    AZURE_CORE_LOGIN_EXPERIENCE_V2=off az login --tenant "$tenantId"
    az account set --subscription "$subscriptionId"
fi

# Remove the service principal secret (OIDC-only, no secret needed)
keyId=$(az ad app credential list --id "$spId" --query "[0].keyId" -o tsv)
if [ -n "$keyId" ]; then
    az ad app credential delete --id "$spId" --key-id "$keyId"
    echo "Temporary secret removed (OIDC-only)..."
fi
