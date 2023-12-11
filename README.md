# SpotifyExporter

This repo contains a set of PowerShell Azure Functions which export Spotify user data (playlists and user library) to `.csv` files in Azure Blob Storage.

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

## Deploy SpotifyExporter resources to Azure

This application can be deployed directly to Azure as a PowerShell Function App.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FRylandDeGregory%2FSpotifyExporter%2Fmaster%2Finfrastructure%2Fmain.json)

Provide the **Spotify Client Id**, **Spotify Client Secret**, and **Spotify Refresh Token** obtained above as the required parameters for the Azure Resource Manager Custom Deployment.

![Sample Azure Deployment](https://github.com/RylandDeGregory/SpotifyExporter/assets/18073815/f549afa8-365c-4894-88a1-d2e688bba5d7)

- To enable diagnostic logging to an Azure Log Analytics Workspace, set the `Logs Enabled` deployment parameter to **true**.
    - _Incurs additional cost for log ingestion and storage_.
- To enable data export to a free-tier Azure Cosmos DB NoSQL Database, set the `Cosmos Enabled` deployment parameter to **true**.
- To disable data export to Azure Storage as `.csv` files, set the `Storage Export Enabled` deployment parameter to **false**.

## Contact and Contribute

If you run into any issues with this repo, please open an issue or pull request.
