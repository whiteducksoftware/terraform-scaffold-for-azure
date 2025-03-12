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

# create service principal if  not exists already
# Needs to be owner to create managed identities and assign roles
if  [[ $(az ad sp list --display-name $spName --query "[].displayName" -o tsv) = "$spName" ]];  then
echo "Service principal already exists..."
export spId=$(az ad sp list --display-name $spName --query "[].appId" -o tsv)
else
   export sp=$(az ad sp create-for-rbac \
    --name "$spName" \
    --role="Owner" \
    --scopes="/subscriptions/$subscriptionId")
echo "Service principal created..."
export spSecret=$(echo "$sp" | jq -r '.password')
export spId=$(echo "$sp" | jq -r '.appId')
# Create federated credential
az ad app federated-credential create --id "$spId" --parameters ./federated_credential.json
echo "Federated credential created..."
fi

# Add API permissions - Group.ReadWrite.All, GroupMember.ReadWrite.All, User.Read.All
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

# Creates resources
az deployment group create \
    --name "$name" \
    --resource-group "$rg" \
    --template-file ./resources.bicep \
    --subscription "$subscriptionId" \
    --mode Incremental \
    --parameters "sa_name=$saName" \
                 "sa_sku=$saSku" \
                 "sc_name=$scName" \
                 "tag=$tag" \
                 "location=$location"
echo "Deployment created..."

# Add Storage Blob Data Owner role assignment
az role assignment create \
    --assignee "$spId" \
    --role "Storage Blob Data Owner" \
    --scope "/subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$saName"
echo "Role for Service Principal created..."

# Map Partner ID (optional)
echo "---"
read -r -p "Do you like to map our Partner ID? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    az extension add --name managementpartner
    az login --tenant "$tenantId" --service-principal -u "$spId" -p "$spSecret"
    az managementpartner create --partner-id 3699617
    az logout
    echo "---"
    echo "Please login."
    az login
fi