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
    --scopes="/subscriptions/$subscriptionId" \
    --years 99)
echo "Service principal created..."
# Set service principal id and secret variables
export spSecret=$(echo "$sp" | jq -r '.password')
export spId=$(echo "$sp" | jq -r '.appId')
fi


# Add ADD API permissions - Group.Create, GroupMember.ReadWrite.All, User.Read.All
az ad app permission add \
    --id "$spId" \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions \
    bf7b1a76-6e77-406b-b258-bf5c7720e98f=Role \
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
    --query [0].value -o tsv)
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

# checks if a password secret already exists and only sets secret value if password doesn't exist
if  [[ $(az keyvault secret list --vault-name "$vaultName"  --query "[].name" -o tsv) = "$spSecret" ]];  then
echo "SP secret already exists..."
else if [ -z "$spSecret" ] # if the variable $spSecret is set then proceed else prompt the user to enter a value
then
  echo "spSecret is not set. Please enter the value:"
  read spSecret
fi
az keyvault secret set --vault-name "$vaultName" \
    --name "sp-secret" \
    --value "$spSecret"
echo "Secrets are saved in vault..."
fi

# Add vault access policy
az keyvault set-policy --name "$vaultName" --spn "$spId" --secret-permissions get list
echo "Policy created in vault..."

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
