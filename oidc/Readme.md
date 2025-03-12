# Terraform scaffold for Azure

This repo contains everything to get started with Terraform on Azure. It sets you up to use the `azurerm` backend with Service Principal authentication via OIDC.

[Terraform Backend Docs for azurerm](https://developer.hashicorp.com/terraform/language/settings/backends/azurerm#backend-azure-ad-service-principal-or-user-assigned-managed-identity-via-oidc-workload-identity-federation)

## What you will get
After executing the below steps you will get:

- a service principal used to run Terraform on behalf
- a Storage Container used to store the Terraform state file

## Requirements

This project requires the following:

- Bash or PowerShell (you can use [Azure Cloud Shell](http://shell.azure.com/))
- for Bash you need to have [jq](https://stedolan.github.io/jq/) installed
- Azure CLI (authenticated)
- the executing user needs Subscription owner access (to give owner access to the Service Principal for creating managed identities and assigning roles) as well as the Application Developer role in EntraId (to create the Service Principal)

## Get started with Bash

Execute the following steps to get started:

1. Authenticate against Azure by executing `az login`
1. Optional: Export your Tenant (`tenantId`) and Subscription ID (`subscriptionId`) if you don't like to deploy with your `az` defaults.
1. Customize `.env` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
1. Update the \<tokens> in `federated_credential.json`.
1. Execute `up.sh` to deploy everything needed
1. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Azure AD). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).

#TODO
## Get started with PowerShell

Execute the following steps to get started:

1. Authenticate against Azure by executing `az login`
1. Optional: Create environment variables for Tenant (`tenantId`) and Subscription ID (`subscriptionId`) or call the script with the parameters `-tenantId` and `-subscriptionId` if you don't like to deploy with your `az` defaults.
1. Customize `.env.powershell` based on your needs and naming conventions (Make sure you met all [Azure naming rules and restrictions](https://docs.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)).
1. Update the \<tokens> in `federated_credential.json`.
1. Execute `up.ps1` to deploy everything needed
1. Grant admin consent for the created app registrations (Terraform will then be allowed to create app registrations and groups in Azure AD). This needs Azure Active Directory global admin access. Find more details on how to grant consent [here](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/grant-admin-consent).


## Disclaimer

The `up.sh` script asks you whether you would like to map our Partner ID to the created Service Principal. Feel free to opt-out or remove the marked lines if you don't like to support us.

> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
