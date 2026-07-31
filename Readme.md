# Terraform scaffold for Azure

This repo contains everything to get started with Terraform on Azure. Choose the authentication method that best fits your CI/CD platform:

| Method | Folder | Description |
|--------|--------|-------------|
| **OIDC (GitHub/Azure DevOps)** | Root (`/`) | Workload Identity Federation for GitHub Actions or Azure DevOps (no secrets needed) - **Recommended** |
| **Client Secret + Key Vault** | [`client-secret/`](client-secret/) | Classic approach using service principal with client secret stored in Key Vault |

---

## Option 1: OIDC Authentication (GitHub Actions / Azure DevOps) - Recommended

This approach uses Workload Identity Federation, eliminating the need for stored secrets. The root folder supports both GitHub Actions and Azure DevOps.

[Terraform Backend Docs for OIDC](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm#backend-azure-ad-service-principal-or-user-assigned-managed-identity-via-oidc-workload-identity-federation)

### What you will get

- A service principal configured for OIDC authentication
- A federated credential for GitHub Actions or Azure DevOps
- A Storage Container used to store the Terraform state file

### Requirements

- Bash or PowerShell (you can use [Azure Cloud Shell](http://shell.azure.com/))
- For Bash you need to have [jq](https://stedolan.github.io/jq/) installed
- Azure CLI (authenticated)
- The executing user needs Subscription Owner access (or Contributor + User Access Administrator/Role Based Access Control Administrator) to create resources and assign Contributor and Role Based Access Control Administrator roles to the Service Principal, as well as the Application Developer role in Entra ID (to create the Service Principal)

### Get started with Bash

1. Authenticate against Azure by executing `az login`
2. Optional: Export your Tenant (`tenantId`) and Subscription ID (`subscriptionId`) if you don't like to deploy with your `az` defaults.
3. Customize `.env` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. **Choose your CI/CD platform** by editing `up.sh`:
   - For GitHub Actions: Set `FEDERATED_CREDENTIAL_FILE="federated_credential_github.json"`
   - For Azure DevOps: Set `FEDERATED_CREDENTIAL_FILE="federated_credential_ado.json"`
5. Update the corresponding federated credential JSON file:
   - **GitHub Actions** (`federated_credential_github.json`):
     - Replace `<organizationName>` with your GitHub organization or username
     - Replace `<organizationId>` with the immutable ID of the GitHub organization or user
     - Replace `<repositoryName>` with your GitHub repository name
     - Replace `<repositoryId>` with the immutable GitHub repository ID
     - Replace `<environment>` with your environment name (e.g., `dev`, `prod`)
     - Follow [Immutable GitHub OIDC subjects](#immutable-github-oidc-subjects) to retrieve the exact subject prefix and, for an existing repository, enable the new format
   - **Azure DevOps** (`federated_credential_ado.json`):
     - Replace `<organizationId>` with your Azure DevOps organization ID (GUID)
     - Replace `<organizationName>` with your Azure DevOps organization name
     - Replace `<projectName>` with your project name
     - Replace `<serviceConnectionName>` with your service connection name
6. Execute `up.sh` to deploy everything needed
7. Add the output secrets to your CI/CD platform settings
8. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

### Get started with PowerShell

1. Authenticate against Azure by executing `az login`
2. Optional: Create environment variables for Tenant (`tenantId`) and Subscription ID (`subscriptionId`) or call the script with the parameters `-tenantId` and `-subscriptionId` if you don't like to deploy with your `az` defaults.
3. Customize `.env.powershell` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. **Choose your CI/CD platform** by editing `up.ps1`:
   - For GitHub Actions: Set `$FEDERATED_CREDENTIAL_FILE = "federated_credential_github.json"`
   - For Azure DevOps: Set `$FEDERATED_CREDENTIAL_FILE = "federated_credential_ado.json"`
5. Update the corresponding federated credential JSON file (see Bash instructions above for details)
6. Execute `up.ps1` to deploy everything needed
7. Add the output secrets to your CI/CD platform settings
8. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

### Federated Credential Configuration (GitHub Actions)

#### Immutable GitHub OIDC subjects

GitHub's default OIDC `sub` claim now binds the owner and repository names to their immutable IDs:

```text
repo:<organizationName>@<organizationId>/<repositoryName>@<repositoryId>:environment:<environment>
```

> **Important:** Repositories created before July 15, 2026 must explicitly opt in to immutable OIDC subjects. Without the opt-in, GitHub continues to issue the legacy name-only subject (`repo:<organizationName>/<repositoryName>:...`), which does not match the immutable Azure federated credential configured by this scaffold.

Repositories created on or after July 15, 2026 use the immutable format automatically. A repository rename or transfer on or after that date also enables the immutable format. This change applies to GitHub.com, not GitHub Enterprise Server.

Use the GitHub API to retrieve the names and immutable IDs and build the new prefix:

```bash
export OWNER="<organizationName>"
export REPOSITORY="<repositoryName>"

gh api \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "repos/$OWNER/$REPOSITORY" \
  --jq '"repo:\(.owner.login)@\(.owner.id)/\(.name)@\(.id)"'
```

Append the required context to the returned prefix, for example `:environment:prod`, and use the result in the Azure federated credential. To migrate without downtime, create this as an additional credential with a unique `name`, then opt the existing repository in so subsequent workflow tokens use the immutable subject:

```bash
gh api \
  --method PUT \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "repos/$OWNER/$REPOSITORY/actions/oidc/customization/sub" \
  -F use_default=true \
  -F use_immutable_subject=true
```

Confirm the active prefix after opting in:

```bash
gh api \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "repos/$OWNER/$REPOSITORY/actions/oidc/customization/sub" \
  --jq '{use_immutable_subject, sub_claim_prefix}'
```

After the workflow authenticates successfully, remove the old name-only Azure credential. Organization administrators can instead enable the format organization-wide through the organization OIDC settings or the corresponding [GitHub Actions OIDC REST API](https://docs.github.com/en/rest/actions/oidc). See the [Microsoft Entra migration guide](https://learn.microsoft.com/en-us/entra/workload-id/workload-identities-github-immutable-subjects) for the complete migration sequence.

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

## Option 2: Client Secret + Key Vault (Classic)

This approach creates a service principal with a client secret and stores all credentials in Azure Key Vault. Use the [`client-secret/`](client-secret/) folder for this method.

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
3. Customize `client-secret/.env` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Execute `client-secret/up.sh` to deploy everything needed
5. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

### Get started with PowerShell

1. Authenticate against Azure by executing `az login`
2. Optional: Create environment variables for Tenant (`tenantId`) and Subscription ID (`subscriptionId`) or call the script with the parameters `-tenantId` and `-subscriptionId` if you don't like to deploy with your `az` defaults.
3. Customize `client-secret/.env.powershell` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Execute `client-secret/up.ps1` to deploy everything needed
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

## Scaffold a Terraform project

There are two approaches for configuring federated credentials with GitHub Actions:

#### Option A: Using `subject` with GitHub Environments (Recommended)

If you are using [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment) (available in GitHub Free for public repositories, and GitHub Pro, Team, and Enterprise for private repositories), you can use the `subject` field with the Azure CLI:

```json
{
    "name": "github-<environment>",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<organizationName>@<organizationId>/<repositoryName>@<repositoryId>:environment:<environment>",
    "description": "GitHub Actions <environment> Environment",
    "audiences": ["api://AzureADTokenExchange"]
}
```

**Advantages:**
- Uses the stable GA (General Availability) Graph API
- Full Azure CLI support via `az ad app federated-credential create`
- Terraform provider compatibility (`azuread_application_federated_identity_credential`)
- Explicit security control per environment

**Limitations:**
- Exact matching only – no wildcards or patterns
- Requires a separate credential for each environment, branch, or pull request scenario
- Maximum of 20 federated credentials per App Registration

#### Option B: Using `claimsMatchingExpression` (Flexible Matching)

If you do not have access to GitHub Environments (e.g., GitHub Free for private repositories) or need flexible pattern matching across multiple branches and pull requests, you must use `claimsMatchingExpression`:

```json
{
    "name": "github-<stage>",
    "issuer": "https://token.actions.githubusercontent.com",
    "claimsMatchingExpression": {
        "value": "claims['sub'] matches 'repo:<organizationName>@<organizationId>/<repositoryName>@<repositoryId>:*' and claims['repository_id'] eq '<repositoryId>'",
        "languageVersion": 1
    },
    "description": "GitHub Actions OIDC for <stage>",
    "audiences": ["api://AzureADTokenExchange"]
}
```

**Advantages:**
- Wildcard and pattern matching (e.g., `repo:org@123/repo@456:*` matches all branches, PRs, and environments; Azure also requires a `repository_id` or `repository_owner_id` condition)
- Single credential can cover multiple scenarios
- Reduces management overhead for dynamic environments

**Limitations:**
- Requires the Microsoft Graph **Beta API** (not GA)
- No native Azure CLI support – must use `az rest` with the Beta endpoint
- No Terraform provider support
- Beta APIs may change without notice

> **Note:** The scripts in this repository use `subject` with GitHub Environments via `az ad app federated-credential create`. If you need flexible pattern matching without environments (e.g., GitHub Free for private repositories), update the federated credential JSON file to use `claimsMatchingExpression` and switch to `az rest` with the Beta Graph API endpoint.

#### claimsMatchingExpression Examples

Match all branches and pull requests:
```json
"claimsMatchingExpression": {
    "value": "claims['sub'] matches 'repo:myorg@123456/myrepo@456789:*' and claims['repository_id'] eq '456789'",
    "languageVersion": 1
}
```

Match only the main branch:
```json
"claimsMatchingExpression": {
    "value": "claims['sub'] == 'repo:myorg@123456/myrepo@456789:ref:refs/heads/main' and claims['repository_id'] eq '456789'",
    "languageVersion": 1
}
```

Match specific environment:
```json
"claimsMatchingExpression": {
    "value": "claims['sub'] == 'repo:myorg@123456/myrepo@456789:environment:production' and claims['repository_id'] eq '456789'",
    "languageVersion": 1
}
```

---

## Scaffold a Terraform project

You will need to tell Terraform where to store its state file. To do so, you need to customize your `main.tf` file based on the below example:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
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
      version = "~> 3.7"
    }
  }
}

provider "azuread" {
  # Configuration options
}
```

[Azure Active Directory Provider Docs](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs)

## Disclaimer

The setup scripts (`up.sh` and `up.ps1`) ask you whether you would like to map our Partner ID to the created Service Principal. Feel free to opt-out or remove the marked lines if you don't like to support us.

> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
