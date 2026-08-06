# SpotifyExporter

This repo contains a set of PowerShell Azure Functions which export Spotify user data (playlists and user library) to `.csv` files in Azure Blob Storage.

The application runs on a Linux [Azure Functions Flex Consumption plan](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan) using PowerShell 7.6. Application releases use One Deploy, with each runnable package stored in a dedicated blob container.

The **SpotifyExporter** application requires the creation of 3 secrets in order to configure the Azure Function to export your Spotify library:

* Spotify Developer Application Client ID
* Spotify Developer Application Client Secret
* Spotify User OAuth 2 Refresh Token

## Spotify Web API Authorization

### Register Spotify Developer Application

Users must obtain a Client ID and Client Secret by registering a [Spotify App](https://developer.spotify.com/documentation/general/guides/app-settings/), as well as an OAuth 2 Refresh token using the [Authorization Code Flow](https://developer.spotify.com/documentation/general/guides/authorization-guide/#authorization-code-flow).

> If you don't know what to use as a Redirect URI, `http://127.0.0.1:8080/spotifyexporter` is a good default.

Once you have created your app, use the `Client ID`, `Client Secret`, and `Redirect URI` as the parameters for [Get-SpotifyRefreshToken.ps1](auth/Get-SpotifyRefreshToken.ps1) in the following section.

### Obtain Refresh Token for a Spotify user

1. Download this repo to your local machine by clicking the Green **Code** button and choosing **Download ZIP**.
2. Unzip `SpotifyExporter.zip` to any folder on your computer.
3. Install or open PowerShell.
    * If you have a Windows computer, launch it by pressing <kbd>Win</kbd> + <kbd>R</kbd> and typing **powershell**.
    * If you have a MacOS computer, install [PowerShell](https://github.com/PowerShell/PowerShell#get-powershell). Launch PowerShell by pressing <kbd>Cmd</kbd> + <kbd>Space</kbd> and typing **PowerShell**.
4. Navigate to the folder where you extracted `SpotifyExporter.zip` using the `cd` command.
    * *Example:* `cd ./Downloads/SpotifyExporter`.
5. Execute the `Get-SpotifyRefreshToken.ps1` script using the values obtained from your Spotify Developer Application.
    * *Example:*

```powershell
./auth/Get-SpotifyRefreshToken.ps1 -ClientId 'c0b51074872b4822b30fe887ce857b47' -ClientSecret '397c93a60153496abbc1458ac1978655' -RedirectUri 'http://127.0.0.1:8080/spotifyexporter'
```

The users's default web browser will open and request them to sign into Spotify, granting read access to their profile for the Spotify Developer Application they registered.

> Users can also execute `Get-SpotifyRefreshToken.ps1` with the `-ManualAuth` switch parameter to prevent the web browser automatically opening. This method will prompt the user to paste a URL into their web browser manually, and then paste the redirect URL into the PowerShell console.

After completing the login process, the user will receive an OAuth 2 Refresh Token in their PowerShell console. **This Refresh Token should be treated as a secret and stored in a safe place**. It will be required in the next step: Azure Resource Manager Custom Deployment.

## Function App deployment

The workflow in [.github/workflows/ci-cd.yaml](.github/workflows/ci-cd.yaml) packages the contents of [src/](src) so `host.json` is at the root of the zip file. Pull requests compile the Bicep template and validate the package layout. Pushes to `master` and manual runs authenticate to Azure with GitHub OIDC, applies infrastructure changes in incremental mode, and then publish through the Flex Consumption One Deploy API.

Flex Consumption stores the active zip in the `app-package` container created by [storage.bicep](infra/modules/storage.bicep). The Function App accesses that container using its user-assigned managed identity. Both SCM and FTP basic publishing credentials are disabled; CI deploys with OIDC and does not require storage keys or a publish profile.

### Configure GitHub Actions

The infrastructure deployment creates a user-assigned identity whose federated credential trusts only this repository's `master` branch. The identity receives resource-group Contributor and Role Based Access Control Administrator roles for infrastructure deployment, plus Website Contributor on the Function App. Configure these GitHub Actions secrets after deploying the infrastructure:

| Secret | Value |
| --- | --- |
| `AZURE_CLIENT_ID` | `githubActionsClientId` deployment output |
| `AZURE_TENANT_ID` | `tenantId` deployment output |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID containing the Function App |
| `AZURE_RESOURCE_GROUP` | Existing resource group containing the deployment |
| `AZURE_FUNCTIONAPP_NAME` | Function App resource name |

The infrastructure stages pass `uniqueSuffix`, `githubBranch`, `githubOwner`, `githubRepository`, and `keyVaultSecretsEnabled=false` inline. Existing Key Vault secrets are therefore left unchanged during CI deployments.

Retrieve the deployment outputs with:

```azurecli
az deployment group show --resource-group <RESOURCE_GROUP> --name <DEPLOYMENT_NAME> --query properties.outputs
```

PowerShell 7.6 support in Azure Functions is currently preview. Change the runtime version in [compute.bicep](infra/modules/compute.bicep) to `7.4` if a GA runtime is required.

## Deploy SpotifyExporter resources to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FRylandDeGregory%2FSpotifyExporter%2Fmaster%2Finfra%2Fmain.json)

Provide the **Spotify Client Id**, **Spotify Client Secret**, and **Spotify Refresh Token** obtained above as the required parameters for the Azure Resource Manager Custom Deployment.

* To enable diagnostic logging to an Azure Log Analytics Workspace, set the `Logs Enabled` deployment parameter to **true**.
    * *Incurs additional Log Analytics cost*.
* To enable data export to a free-tier Azure Cosmos DB NoSQL Database, set the `Cosmos Enabled` deployment parameter to **true**.
* To disable data export to Azure Storage as `.csv` files, set the `Storage Export Enabled` deployment parameter to **false**.

The Function App integrates with a delegated subnet that has Storage and Key Vault service endpoints. Both services default-deny network access and allow the integration subnet. Service endpoints keep traffic on the Azure backbone and avoid private endpoint charges, but the services retain public DNS endpoints.

### What gets deployed

The infrastructure is defined in [infra/main.bicep](infra/main.bicep), which orchestrates multiple focused modules:

| Module | Resources |
| --- | --- |
| [cicd.bicep](infra/modules/cicd.bicep) | GitHub Actions deployment identity, OIDC credential, infrastructure roles, and Function App deployment role |
| [compute.bicep](infra/modules/compute.bicep) | Flex Consumption plan, Function App, and application managed identity |
| [cosmos.bicep](infra/modules/cosmos.bicep) | (if enabled) Cosmos DB NoSQL account, database, and containers |
| [keyvault.bicep](infra/modules/keyvault.bicep) | Key Vault and the three Spotify secrets |
| [monitoring.bicep](infra/modules/monitoring.bicep) | Log Analytics Workspace and Application Insights |
| [network.bicep](infra/modules/network.bicep) | Virtual network and delegated Flex Consumption integration subnet |
| [rbac.bicep](infra/modules/rbac.bicep) | Azure RBAC and Cosmos SQL RBAC Role assignments for the Function App managed identity |
| [storage.bicep](infra/modules/storage.bicep) | Network-restricted Storage Account for deployment packages, `.csv` export, and Functions host state |

To deploy from the CLI:

```azurecli
az deployment group create --resource-group <RESOURCE_GROUP> --template-file infra/main.bicep --parameters spotifyClientId=<CLIENT_ID> spotifyClientSecret=<CLIENT_SECRET> spotifyRefreshToken=<REFRESH_TOKEN>
```

## Contact and Contribute

If you run into any problems with this repo, or if you have any questions, please open an issue.
