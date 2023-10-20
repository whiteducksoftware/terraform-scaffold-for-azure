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
export sp=$(az ad sp create-for-rbac --name $spName --role="Owner" --scopes="/subscriptions/$subscriptionId" --years 99)

if test $? -ne 0
then
    echo "service principal couldn't be created..."
    exit
else
    echo "service principal created..."
fi

# gets id and secret
export spSecret=$(echo $sp | jq -r '.password')
export spId=$(echo $sp | jq -r '.appId')

# add ADD API permissions - Group.Create, GroupMember.ReadWrite.All, User.Read.All
az ad app permission add \
    --id $spId \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions \
    bf7b1a76-6e77-406b-b258-bf5c7720e98f=Role \
    dbaae8cf-10b5-4b86-a4a1-f871c94c6695=Role \
    df021288-bdef-4463-88db-98f22de89214=Role

if test $? -ne 0
then
    echo "service principal couldn't be authorized..."
    exit
else
    echo "service principal authorized..."
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

# get local user
export userId=$(az ad signed-in-user show --query id -o tsv)

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
    --template-file ./resources.bicep \
    --subscription $subscriptionId \
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
