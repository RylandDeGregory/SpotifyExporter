# SpotifyExporter

This repo contains a set of PowerShell Azure Functions which export Spotify user data (playlists and user library) to `.csv` files in Azure Blob Storage.

The application runs as a container image on [Azure Functions hosted in Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/functions-overview). The image is published to the GitHub Container Registry (GHCR) and pulled by Azure at deployment time.

The **SpotifyExporter** application requires the creation of 3 secrets in order to configure the Azure Function to export your Spotify library:

* Spotify Developer Application Client ID
* Spotify Developer Application Client Secret
* Spotify User OAuth 2 Refresh Token

## Spotify Web API Authorization

### Register Spotify Developer Application

Users must obtain a Client ID and Client Secret by registering a [Spotify App](https://developer.spotify.com/documentation/general/guides/app-settings/), as well as an OAuth 2 Refresh token using the [Authorization Code Flow](https://developer.spotify.com/documentation/general/guides/authorization-guide/#authorization-code-flow).

> If you don't know what to use as a Redirect URI, http://localhost:8080/spotifyexporter is a good default.

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
./auth/Get-SpotifyRefreshToken.ps1 -ClientId 'c0b51074872b4822b30fe887ce857b47' -ClientSecret '397c93a60153496abbc1458ac1978655' -RedirectUri 'http://localhost:8080/spotifyexporter'
```

The users's default web browser will open and request them to sign into Spotify, granting read access to their profile for the Spotify Developer Application they registered.

> Users can also execute `Get-SpotifyRefreshToken.ps1` with the `-ManualAuth` switch parameter to prevent the web browser automatically opening. This method will prompt the user to paste a URL into their web browser manually, and then paste the redirect URL into the PowerShell console.

After completing the login process, the user will receive an OAuth 2 Refresh Token in their PowerShell console. **This Refresh Token should be treated as a secret and stored in a safe place**. It will be required in the next step: Azure Resource Manager Custom Deployment.

## The container image

The function code in [src/](src) is packaged into a container image built from the official [Azure Functions PowerShell base image](https://mcr.microsoft.com/en-us/product/azure-functions/powershell/about).

### How the image is consumed

The `containerImage` bicep parameter controls which image the Container App runs, defaulting to `ghcr.io/rylanddegregory/spotifyexporter:latest`. Pin it to a released version for reproducible deployments, i.e. `ghcr.io/rylanddegregory/spotifyexporter:3.0.0`

Because Container Apps hosting does not support the Functions built-in continuous deployment feature, updating the app after pushing a new image is an explicit step:

```azurecli
az containerapp update --name <FUNCTION_APP_NAME> --resource-group <RESOURCE_GROUP> --image ghcr.io/rylanddegregory/spotifyexporter:<TAG>
```

### Base image maintenance

MCR does not publish a floating `4-powershell7.6` tag, so the [Dockerfile](Dockerfile) pins an explicit PowerShell 7.6 runtime build **by digest**. Bump it to pick up Functions runtime and PowerShell security updates. Switch to `4-powershell7.4` if you prefer a floating tag that updates automatically.

## Deploy SpotifyExporter resources to Azure

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FRylandDeGregory%2FSpotifyExporter%2Fmaster%2Finfra%2Fmain.json)

Provide the **Spotify Client Id**, **Spotify Client Secret**, and **Spotify Refresh Token** obtained above as the required parameters for the Azure Resource Manager Custom Deployment.

![Sample Azure Template Deployment](https://github.com/RylandDeGregory/SpotifyExporter/assets/18073815/89fe1d6a-fc57-40a2-b863-9569448be967)

* To enable diagnostic logging to an Azure Log Analytics Workspace, set the `Logs Enabled` deployment parameter to **true**.
    * *Incurs additional Log Analytics cost*.
* To enable data export to a free-tier Azure Cosmos DB NoSQL Database, set the `Cosmos Enabled` deployment parameter to **true**.
* To disable data export to Azure Storage as `.csv` files, set the `Storage Export Enabled` deployment parameter to **false**.
* To deploy a specific build instead of `latest`, set the `Container Image` deployment parameter.

### What gets deployed

The infrastructure is defined in [infra/main.bicep](infra/main.bicep), which orchestrates multiple focused modules:

| Module | Resources |
| --- | --- |
| [compute.bicep](infra/modules/compute.bicep) | Container Apps Environment and the Function App |
| [cosmos.bicep](infra/modules/cosmos.bicep) | (if enabled) Cosmos DB NoSQL account, database, and containers |
| [keyvault.bicep](infra/modules/keyvault.bicep) | Key Vault and the three Spotify secrets |
| [monitoring.bicep](infra/modules/monitoring.bicep) | Log Analytics Workspace and Application Insights |
| [network.bicep](infra/modules/network.bicep) | Virtual Network and delegated Container Apps subnet with service endpoints |
| [rbac.bicep](infra/modules/rbac.bicep) | Azure RBAC and Cosmos SQL RBAC Role assignments for the Function App managed identity |
| [storage.bicep](infra/modules/storage.bicep) | Storage Account for `.csv` export and the Functions host storage |

To deploy from the CLI:

```azurecli
az deployment group create --resource-group <RESOURCE_GROUP> --template-file infra/main.bicep --parameters spotifyClientId=<CLIENT_ID> spotifyClientSecret=<CLIENT_SECRET> spotifyRefreshToken=<REFRESH_TOKEN>
```

## Contact and Contribute

If you run into any problems with this repo, or if you have any questions, please open an issue.
