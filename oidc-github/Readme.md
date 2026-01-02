# Terraform scaffold for Azure (GitHub Actions OIDC)

This folder contains everything to get started with Terraform on Azure using **GitHub Actions** with OIDC authentication. It sets you up to use the `azurerm` backend with Service Principal authentication via OIDC (Workload Identity Federation).

> **Note:** For Azure DevOps OIDC, see the [oidc](../oidc/) folder.

[Terraform Backend Docs for azurerm](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm#backend-azure-ad-service-principal-or-user-assigned-managed-identity-via-oidc-workload-identity-federation)

## What you will get

After executing the below steps you will get:

- A service principal configured for GitHub Actions OIDC authentication
- A federated credential using `claimsMatchingExpression` for flexible repository/branch matching
- A Storage Container used to store the Terraform state file

## Requirements

This project requires the following:

- Bash or PowerShell (you can use [Azure Cloud Shell](http://shell.azure.com/))
- For Bash you need to have [jq](https://stedolan.github.io/jq/) installed
- Azure CLI (authenticated)
- the executing user needs Subscription Owner access (or Contributor + User Access Administrator/Role Based Access Control Administrator) to create resources and assign Contributor and Role Based Access Control Administrator roles to the Service Principal, as well as the Application Developer role in Entra ID (to create the Service Principal)

## Get started with Bash

Execute the following steps to get started:

1. Authenticate against Azure by executing `az login`
2. Optional: Export your Tenant (`tenantId`) and Subscription ID (`subscriptionId`) if you don't like to deploy with your `az` defaults.
3. Customize `.env` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Update `federated_credential.json`:
   - Replace `<stage>` with your environment name (e.g., `dev`, `prod`)
   - Replace `<organizationName>` with your GitHub organization or username
   - Replace `<repositoryName>` with your GitHub repository name
5. Execute `up.sh` to deploy everything needed
6. Add the output secrets to your GitHub repository settings
7. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

## Get started with PowerShell

Execute the following steps to get started:

1. Authenticate against Azure by executing `az login`
2. Optional: Create environment variables for Tenant (`tenantId`) and Subscription ID (`subscriptionId`) or call the script with the parameters `-tenantId` and `-subscriptionId` if you don't like to deploy with your `az` defaults.
3. Customize `.env.powershell` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
4. Update `federated_credential.json`:
   - Replace `<stage>` with your environment name (e.g., `dev`, `prod`)
   - Replace `<organizationName>` with your GitHub organization or username
   - Replace `<repositoryName>` with your GitHub repository name
5. Execute `up.ps1` to deploy everything needed
6. Add the output secrets to your GitHub repository settings
7. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Entra ID). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

## Federated Credential Configuration

The `federated_credential.json` uses `claimsMatchingExpression` which provides more flexibility than the traditional `subject` field. The pattern `repo:<org>/<repo>:*` matches all branches and environments.

### Examples

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

## GitHub Actions Workflow Example

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

## Disclaimer

The `up.sh` script asks you whether you would like to map our Partner ID to the created Service Principal. Feel free to opt-out or remove the marked lines if you don't like to support us.

> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
