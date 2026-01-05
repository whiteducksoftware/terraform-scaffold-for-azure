# Terraform scaffold for Azure

This repo contains everything to get started with Terraform on Azure. Choose the authentication method that best fits your CI/CD platform:

| Method | Folder | Description |
|--------|--------|-------------|
| **Client Secret + Key Vault** | Root (`/`) | Classic approach using service principal with client secret stored in Key Vault |
| **GitHub Actions OIDC** | [`oidc-github/`](oidc-github/) | Workload Identity Federation for GitHub Actions (no secrets needed) |
| **Azure DevOps OIDC** | [`oidc-ado/`](oidc-ado/) | Workload Identity Federation for Azure DevOps Pipelines (no secrets needed) |

---

## Option 1: Client Secret + Key Vault (Classic)

This approach creates a service principal with a client secret and stores all credentials in Azure Key Vault.

### What you will get

- A service principal used to run Terraform on behalf
- A Storage Container used to store the Terraform state file
- A Key Vault containing all secrets to allow easy and secure access

### Requirements

- Bash or PowerShell (you can use [Azure Cloud Shell](http://shell.azure.com/))
- For Bash you need to have [jq](https://stedolan.github.io/jq/) installed
- Azure CLI (authenticated)
- The executing user needs Subscription Owner access (or Contributor + User Access Administrator/Role Based Access Control Administrator) to create resources and assign Contributor and Role Based Access Control Administrator roles to the Service Principal, as well as the Application Developer role in Entra ID (to create the Service Principal)

### Get started with Bash

1. Authenticate against Azure by executing `az login`
2. Optional: Export your Tenant (`tenantId`) and Subscription ID (`subscriptionId`) if you don't like to deploy with your `az` defaults.
3. Customize `.env` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Execute `up.sh` to deploy everything needed
5. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

### Get started with PowerShell

1. Authenticate against Azure by executing `az login`
2. Optional: Create environment variables for Tenant (`tenantId`) and Subscription ID (`subscriptionId`) or call the script with the parameters `-tenantId` and `-subscriptionId` if you don't like to deploy with your `az` defaults.
3. Customize `.env.powershell` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Execute `up.ps1` to deploy everything needed
5. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

### Initialize Terraform with Key Vault secrets

We do not recommend storing any secrets and credentials in code. Therefore everything needed will be requested from Key Vault as needed:

```bash
#!/bin/bash

# customize your subscription id and resource group name
export subscriptionId="00000000-0000-0000-0000-000000000000"
export rg="my-rg"

# sets subscription;
az account set --subscription $subscriptionId

# get vault
export vaultName=$(az keyvault list --subscription=$subscriptionId -g $rg --query '[0].{name:name}' -o tsv)

## extracts and exports secrets
export saKey=$(az keyvault secret show --subscription=$subscriptionId --vault-name="$vaultName" --name sa-key --query value -o tsv)
export saName=$(az keyvault secret show --subscription=$subscriptionId --vault-name="$vaultName" --name sa-name --query value -o tsv)
export scName=$(az keyvault secret show --subscription=$subscriptionId --vault-name="$vaultName" --name sc-name --query value -o tsv)
export spSecret=$(az keyvault secret show --subscription=$subscriptionId --vault-name="$vaultName" --name sp-secret --query value -o tsv)
export spId=$(az keyvault secret show --subscription=$subscriptionId --vault-name="$vaultName" --name sp-id --query value -o tsv)

# exports secrets
export ARM_SUBSCRIPTION_ID=$subscriptionId
export ARM_TENANT_ID=$tenantId
export ARM_CLIENT_ID=$spId
export ARM_CLIENT_SECRET=$spSecret

# runs Terraform init
terraform init -input=false \
  -backend-config="access_key=$saKey" \
  -backend-config="storage_account_name=$saName" \
  -backend-config="container_name=$scName"
```

---

## Option 2: GitHub Actions OIDC

This approach uses Workload Identity Federation with GitHub Actions, eliminating the need for stored secrets.

[Terraform Backend Docs for OIDC](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm#backend-azure-ad-service-principal-or-user-assigned-managed-identity-via-oidc-workload-identity-federation)

### What you will get

- A service principal configured for GitHub Actions OIDC authentication
- A federated credential using `claimsMatchingExpression` for flexible repository/branch matching
- A Storage Container used to store the Terraform state file

### Requirements

- Bash or PowerShell (you can use [Azure Cloud Shell](http://shell.azure.com/))
- For Bash you need to have [jq](https://stedolan.github.io/jq/) installed
- Azure CLI (authenticated)
- The executing user needs Subscription Owner access (or Contributor + User Access Administrator/Role Based Access Control Administrator) to create resources and assign Contributor and Role Based Access Control Administrator roles to the Service Principal, as well as the Application Developer role in Entra ID (to create the Service Principal)

### Get started with Bash

1. Authenticate against Azure by executing `az login`
2. Optional: Export your Tenant (`tenantId`) and Subscription ID (`subscriptionId`) if you don't like to deploy with your `az` defaults.
3. Customize `oidc-github/.env` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Update `oidc-github/federated_credential.json`:
   - Replace `<stage>` with your environment name (e.g., `dev`, `prod`)
   - Replace `<organizationName>` with your GitHub organization or username
   - Replace `<repositoryName>` with your GitHub repository name
5. Execute `oidc-github/up.sh` to deploy everything needed
6. Add the output secrets to your GitHub repository settings
7. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

### Get started with PowerShell

1. Authenticate against Azure by executing `az login`
2. Optional: Create environment variables for Tenant (`tenantId`) and Subscription ID (`subscriptionId`) or call the script with the parameters `-tenantId` and `-subscriptionId` if you don't like to deploy with your `az` defaults.
3. Customize `oidc-github/.env.powershell` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Update `oidc-github/federated_credential.json`:
   - Replace `<stage>` with your environment name (e.g., `dev`, `prod`)
   - Replace `<organizationName>` with your GitHub organization or username
   - Replace `<repositoryName>` with your GitHub repository name
5. Execute `oidc-github/up.ps1` to deploy everything needed
6. Add the output secrets to your GitHub repository settings
7. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

### Federated Credential Configuration

The `federated_credential.json` uses `claimsMatchingExpression` which provides more flexibility than the traditional `subject` field. The pattern `repo:<org>/<repo>:*` matches all branches and environments.

#### Examples

Match all branches and pull requests:
```json
"claimsMatchingExpression": {
    "value": "claims['sub'] matches 'repo:myorg/myrepo:*'",
    "languageVersion": 1
}
```

Match only the main branch:
```json
"claimsMatchingExpression": {
    "value": "claims['sub'] == 'repo:myorg/myrepo:ref:refs/heads/main'",
    "languageVersion": 1
}
```

Match specific environment:
```json
"claimsMatchingExpression": {
    "value": "claims['sub'] == 'repo:myorg/myrepo:environment:production'",
    "languageVersion": 1
}
```

### GitHub Actions Workflow Example

```yaml
name: Terraform

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init

      - name: Terraform Plan
        run: terraform plan
```

---

## Option 3: Azure DevOps OIDC

This approach uses Workload Identity Federation with Azure DevOps Pipelines, eliminating the need for stored secrets.

[Terraform Backend Docs for OIDC](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm#backend-azure-ad-service-principal-or-user-assigned-managed-identity-via-oidc-workload-identity-federation)

### What you will get

- A service principal configured for Azure DevOps OIDC authentication
- A federated credential for your Azure DevOps organization/project
- A Storage Container used to store the Terraform state file

### Requirements

- Bash or PowerShell (you can use [Azure Cloud Shell](http://shell.azure.com/))
- For Bash you need to have [jq](https://stedolan.github.io/jq/) installed
- Azure CLI (authenticated)
- The executing user needs Subscription Owner access (or Contributor + User Access Administrator/Role Based Access Control Administrator) to create resources and assign Contributor and Role Based Access Control Administrator roles to the Service Principal, as well as the Application Developer role in Entra ID (to create the Service Principal)

### Get started with Bash

1. Authenticate against Azure by executing `az login`
2. Optional: Export your Tenant (`tenantId`) and Subscription ID (`subscriptionId`) if you don't like to deploy with your `az` defaults.
3. Customize `oidc-ado/.env` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Update the `<tokens>` in `oidc-ado/federated_credential.json`.
5. Execute `oidc-ado/up.sh` to deploy everything needed
6. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

### Get started with PowerShell

1. Authenticate against Azure by executing `az login`
2. Optional: Create environment variables for Tenant (`tenantId`) and Subscription ID (`subscriptionId`) or call the script with the parameters `-tenantId` and `-subscriptionId` if you don't like to deploy with your `az` defaults.
3. Customize `oidc-ado/.env.powershell` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Update the `<tokens>` in `oidc-ado/federated_credential.json`.
5. Execute `oidc-ado/up.ps1` to deploy everything needed
6. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

---

## Scaffold a Terraform project

You will need to tell Terraform where to store its state file. To do so, you need to customize your `main.tf` file based on the below example:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.77"
    }
  }
  backend "azurerm" {
    key = "azure.tfstate"
  }
}

provider "azurerm" {
  features {}
}
```

[Terraform Backend Docs for azurerm](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm)

[Azure Provider Docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Azuread provider configuration

```hcl
terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.44"
    }
  }
}

provider "azuread" {
  # Configuration options
}
```

[Azure Active Directory Provider Docs](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs)

## Disclaimer

The `up.sh` script asks you whether you would like to map our Partner ID to the created Service Principal. Feel free to opt-out or remove the marked lines if you don't like to support us.

> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
