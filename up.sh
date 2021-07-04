#!/bin/bash
# used to bootstrap infrastructure required my Terraform
set -a -e

# check and export subscription/tenant if needed
if [ "$subscriptionId" = "" ]
  then
    export subscriptionId=$(az account show --query id -o tsv)
    if test $? -ne 0
      then
        echo "subscription couldn't be exported..."
        exit
      else
        echo "subscription exported..."
    fi
  else
    echo "subscription details are set..."
fi

if [ "$tenantId" = "" ]
  then
    export tenantId=$(az account show --query homeTenantId -o tsv)
    if test $? -ne 0
      then
        echo "tenant couldn't be exported..."
        exit
      else
        echo "tenant exported..."
    fi
  else
    echo "tenant details are set..."
fi

# sources variables
if [ -f ".env" ]; then
  source .env
fi

# set subscription
az account set --subscription $subscriptionId

# creates resource group
az group create --name "$rg" --location "$location" --tags environment=$tag --subscription $subscriptionId

if test $? -ne 0
then
    echo "resources group couldn't be created..."
    exit
else
    echo "resources group created..."
fi

# creates a service principal
# needs to be owner to be able to enable future service principals
export sp=$(az ad sp create-for-rbac --name $spName --role="Owner" --scopes="/subscriptions/$subscriptionId" --years 99 -o tsv)

if test $? -ne 0
then
    echo "service principal couldn't be created..."
    exit
else
    echo "service principal created..."
fi

# gets id and secret
export spSecret=$(echo $sp | awk '{print $4}')
export spId=$(echo $sp | awk '{print $1}')

# add ADD API permissions (read and create apps and groups)
az ad app permission add \
    --id $spId \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions \
    0e263e50-5827-48a4-b97c-d940288653c7=Scope \
    c5366453-9fb0-48a5-a156-24f0c49a4b84=Scope \
    4e46008b-f24c-477d-8fff-7bb4ec7aafe0=Scope \
    e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope \
    bdfbf15f-ee85-4955-8675-146e8e5296b5=Scope \
    bf7b1a76-6e77-406b-b258-bf5c7720e98f=Role \
    19dbc75e-c2e2-444c-a770-ec69d8559fc7=Role \
    62a82d76-70ea-41e2-9197-370581804d09=Role \
    18a4783c-866b-4cc7-a460-3d5e5662c884=Role \
    1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9=Role

if test $? -ne 0
then
    echo "service principal couldn't be authorized..."
    exit
else
    echo "service principal authorized..."
fi

# get local user
export userMail=$(az account show --query user.name -o tsv)
export userId=$(az ad user show --id $userMail --query objectId -o tsv)

if test $? -ne 0
then
    echo "local user id cound't be fetched..."
    exit
else
    echo "local user fetched..."
fi

# creates resources
az deployment group create \
    --name $name \
    --resource-group $rg \
    --template-file ./resources.json \
    --subscription $subscriptionId \
    --mode Incremental \
    --parameters "vault_name=$vaultName" \
                 "sa_name=$saName" \
                 "sc_name=$scName" \
                 "tenant_id=$tenantId" \
                 "user_id=$userId" \
                 "tag"=$tag \
                 "location"=$location

if test $? -ne 0
then
    echo "deployment couldn't be created..."
    exit
else
    echo "deployment created..."
fi

# gets storage account key
export saKey=$(az storage account keys list --subscription=$subscriptionId --resource-group $rg --account-name $saName --query [0].value -o tsv)

if test $? -ne 0
then
    echo "storage container couldn't be created..."
    exit
else
    echo "storage container created..."
fi

# saves storage account details to vault
az keyvault secret set --vault-name $vaultName \
    --name "sa-key" \
    --value "$saKey"
az keyvault secret set --vault-name $vaultName \
    --name "sa-name" \
    --value "$saName"
az keyvault secret set --vault-name $vaultName \
    --name "sc-name" \
    --value "$scName"

if test $? -ne 0
then
    echo "secrets couldn't be saved..."
    exit
else
    echo "secrets are saved in vault..."
fi

# save secrets to vault
az keyvault secret set --vault-name $vaultName \
    --name "sp-id" \
    --value "$spId"
az keyvault secret set --vault-name $vaultName \
    --name "sp-secret" \
    --value "$spSecret"

if test $? -ne 0
then
    echo "secrets couldn't be saved..."
    exit
else
    echo "secrets are saved in vault..."
fi

# update roles
az role assignment create --assignee $spId --scope "/subscriptions/$subscriptionId" --role "Monitoring Metrics Publisher"

if test $? -ne 0
then
    echo "roles couldn't be saved..."
    exit
else
    echo "roles are saved in vault..."
fi

# add vault access policy
az keyvault set-policy --name $vaultName --spn $spId --secret-permissions get list

if test $? -ne 0
then
    echo "policy couldn't be created in vault..."
    exit
else
    echo "policy created in vault..."
fi

### 
# The below lines will map our Partner id to the Terraform service principal
# Feel free to delete the lines below

echo "---"
read -r -p "Do you like to map our Partner ID? [y/N] " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  export currentSubscription=$(az account show --query id -o tsv)

  az extension add --name managementpartner
  az login --tenant $tenantId --service-principal -u $spId -p $spSecret
  az managementpartner create --partner-id 3699617
  az logout
  echo "---"
  echo "Please login."
  az login
fi
###
