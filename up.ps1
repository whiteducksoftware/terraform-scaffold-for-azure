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
$saName = "stac0$($configuration.name)$($configuration.suffix)$id"
$scName = "blob0$($configuration.name)$($configuration.suffix)$id"
$vaultName = "akv-$($configuration.name)-$($configuration.suffix)-$id"

# set subscription
az account set --subscription $subscriptionId

# creates resource group
try {
    az group create --name "$rg" --location "$location" --tags environment=$tag --subscription $subscriptionId
    Write-Host "resource group created..."
}
catch {
    Write-Host "resource group could not be created"
    Write-Host $_
    break
}

# creates a service principal
# needs to be owner to be able to enable future service principals
try {
    $sp = az ad sp create-for-rbac --name $spName --role="Owner" --scopes="/subscriptions/$subscriptionId" --years 99 -o json | ConvertFrom-Json
    Write-Host "service principal created..."
}
catch {
    Write-Host "service principal could not be created..."
    Write-Host $_
    break
}

# gets id and secret
$spSecret = $sp.password
$spId = $sp.appId

# add ADD API permissions (read and create apps and groups)
try {
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

    Write-Host "service principal authorized..."
}
catch {
    Write-Host "service principal couldn't be authorized..."
    Write-Host $_
    break
}

# get local user
try {
    $userMail = az account show --query user.name -o tsv
    $userId = az ad user show --id $userMail --query objectId -o tsv
    Write-Host "local user fetched..."
}
catch {
    Write-Host "local user id cound't be fetched..."
    Write-Host $_
    break
}

# creates resources
try {
    az deployment group create `
    --name $name `
    --resource-group $rg `
    --template-file ./resources.json `
    --subscription $subscriptionId `
    --mode Incremental `
    --parameters "vault_name=$vaultName" `
                 "sa_name=$saName" `
                 "sc_name=$scName" `
                 "tenant_id=$tenantId" `
                 "user_id=$userId" `
                 "tag"=$tag `
                 "location"=$location

    Write-Host "deployment created..."

}
catch {
    Write-Host "deployment couldn't be created..."
    Write-Host $_
    break
}