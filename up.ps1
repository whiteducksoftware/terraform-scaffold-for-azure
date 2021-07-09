[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $subscriptionId = (az account show --query id -o tsv),

    [Parameter()]
    [string]
    $tenantId = (az account show --query homeTenantId -o tsv)
)

$id = Get-Random -Minimum 1000 -Maximum 10000

$configuration = Get-content .\config.json | ConvertFrom-Json

$spName = "tfprovision-$($configuration.suffix)-sp"
$rg = "$($configuration.name)-$($configuration.suffix)-rg"
$tag = "$($configuration.suffix)"
$saName = "stac0$($configuration.name)0$($configuration.suffix)0$id"
$scName = "blob0$($configuration.name)0$($configuration.suffix)0$id"
$vaultName = "akv-$($configuration.name)-$($configuration.suffix)-$id"

# set subscription
az account set --subscription $subscriptionId

# creates resource group
az group create --name $rg --location $configuration.location --tags environment=$tag --subscription $subscriptionId

if ($LASTEXITCODE -eq "2") {
    Write-Host "resource group could not be created"
    break
}
else {
    Write-Host "resources group created..."
}

# creates a service principal
# needs to be owner to be able to enable future service principals
$sp = az ad sp create-for-rbac --name $spName --role="Owner" --scopes="/subscriptions/$subscriptionId" --years 99 -o json | ConvertFrom-Json

if ($LASTEXITCODE -eq "2") {
    Write-Host "service principal could not be created..."
    break
}
else {
    Write-Host "service principal created..."
}

# gets id and secret
$spSecret = $sp.password
$spId = $sp.appId

# add ADD API permissions (read and create apps and groups)
az ad app permission add `
    --id $spId `
    --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions `
    0e263e50-5827-48a4-b97c-d940288653c7=Scope `
    c5366453-9fb0-48a5-a156-24f0c49a4b84=Scope `
    4e46008b-f24c-477d-8fff-7bb4ec7aafe0=Scope `
    e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope `
    bdfbf15f-ee85-4955-8675-146e8e5296b5=Scope `
    bf7b1a76-6e77-406b-b258-bf5c7720e98f=Role `
    19dbc75e-c2e2-444c-a770-ec69d8559fc7=Role `
    62a82d76-70ea-41e2-9197-370581804d09=Role `
    18a4783c-866b-4cc7-a460-3d5e5662c884=Role `
    1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9=Role

if ($LASTEXITCODE -eq "2") {
    Write-Host "service principal could not be authorized..."
    break
}
else {
    Write-Host "service principal authorized..."
}


# get local user
$userMail = az account show --query user.name -o tsv
$userId = az ad user show --id $userMail --query objectId -o tsv

if ($LASTEXITCODE -eq "2") {
    Write-Host "local user id cound't be fetched..."
    break
}
else {
    Write-Host "local user fetched..."
}

# creates resources
az deployment group create `
--name $configuration.name `
--resource-group $rg `
--template-file .\resources.json `
--subscription $subscriptionId `
--mode Incremental `
--parameters "vault_name=$vaultName" `
                "sa_name=$saName" `
                "sc_name=$scName" `
                "tenant_id=$tenantId" `
                "user_id=$userId" `
                "tag=$tag" `
                "location=$($configuration.location)"

if ($LASTEXITCODE -eq "2") {
    Write-Host "deployment could not be created..."
    break
}
else {
    Write-Host "deployment created..."
}


# gets storage account key
$saKey = az storage account keys list --subscription=$subscriptionId --resource-group $rg --account-name $saName --query [0].value -o tsv

if ($LASTEXITCODE -eq "2") {
    Write-Host "storage container could not be created..."
    break
}
else {
    Write-Host "storage container created..."
}

# saves storage account details to vault
az keyvault secret set --vault-name $vaultName `
--name "sa-key" `
--value $saKey
az keyvault secret set --vault-name $vaultName `
--name "sa-name" `
--value $saName
az keyvault secret set --vault-name $vaultName `
--name "sc-name" `
--value $scName
az keyvault secret set --vault-name $vaultName `
--name "sp-id" `
--value $spId
az keyvault secret set --vault-name $vaultName `
--name "sp-secret" `
--value $spSecret

if ($LASTEXITCODE -eq "2") {
    Write-Host "secrets could not be saved..."
    break
}
else {
    Write-Host "secrets are saved in vault..."
}


# update roles
az role assignment create --assignee $spId --scope "/subscriptions/$subscriptionId" --role "Monitoring Metrics Publisher"

if ($LASTEXITCODE -eq "2") {
    Write-Host "roles could not be saved..."
    break
}
else {
    Write-Host "roles are saved in vault..."
}

# add vault access policy
az keyvault set-policy --name $vaultName --spn $spId --secret-permissions get list

if ($LASTEXITCODE -eq "2") {
    Write-Host "policy could not be created in vault..."
    break
}
else {
    Write-Host "policy created in vault..."
}


### 
# The below lines will map our Partner id to the Terraform service principal
Write-Host "---"
$confirmation = Read-Host "Do you like to map our Partner ID? [y/N]"
if ($confirmation -match 'y') {
    $currentSubscription = az account show --query id -o tsv
    az extension add --name managementpartner
    az login --tenant $tenantId --service-principal -u $spId -p $spSecret
    az managementpartner create --partner-id 3699617
    az logout
    Write-Host "---"
    Write-Host "Please login."
    az login
}