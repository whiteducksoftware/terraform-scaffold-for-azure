$ErrorActionPreference = "Stop"

# check and export subscription/tenant if needed
if (-not (Test-Path env:subscriptionId)) 
{
    try {
        $env:subscriptionId = az account show --query id -o tsv
        Write-Host "subscription exported..."
    }
    catch {
        Write-Host "subscription could not be exported..."
        Write-Host $_
        break
    }
}
else 
{
    Write-Host "subscription details are set..."
}

if (-not (Test-Path env:tenantId)) 
{
    try {
        $env:tenantId = az account show --query homeTenantId -o tsv
        Write-Host "tenant exported..."
    }
    catch {
        Write-Host "tenant could not be exported..."
        Write-Host $_
        break
    }
}
else 
{
    Write-Host "tenant details are set..."
}

# set variables
try {
    .\vars.ps1
    Write-Host "setting variables..."
}
catch {
    Write-Host "variables could not be set"
    Write-Host $_
    break
}

# set subscription
az account set --subscription $env:subscriptionId

# creates resource group
try {
    az group create --name "$env:rg" --location "$env:location" --tags environment=$env:tag --subscription $env:subscriptionId
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
    $sp = az ad sp create-for-rbac --name $env:spName --role="Owner" --scopes="/subscriptions/$env:subscriptionId" --years 99 -o tsv
    Write-Host "service principal created..."
}
catch {
    Write-Host "service principal could not be created..."
    Write-Host $_
    break
}
