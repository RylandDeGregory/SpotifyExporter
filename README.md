# SpotifyExporter

This repo contains a set of PowerShell Azure Functions which export Spotify user data (playlists and user library) to `.csv` files in Azure Blob Storage.

## Spotify Web API Authorization

Users must obtain a Client ID and Client Secret by registering a [Spotify App](https://developer.spotify.com/documentation/general/guides/app-settings/), as well as an OAuth 2 Refresh token using the [Authorization Code Flow](https://developer.spotify.com/documentation/general/guides/authorization-guide/#authorization-code-flow).

I have modified and re-hosted Spotify's example Node.js application that grants an OAuth 2 Refresh token. Follow the instructions in my [SpotifyWebAPIAuth](https://github.com/RylandDeGregory/SpotifyWebAPIAuth) GitHub repo to both register a Spotify app and obtain an OAuth 2 Refresh token that can access your user profile using the Spotify Web API.

## Implementation

This repo can be deployed directly to Azure as a PowerShell Function App.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FRylandDeGregory%2FSpotifyExporter%2Fmaster%2Finfrastructure%2Fmain.json)

## Contact and Contribute

If you run into any issues with this repo, please open an issue or pull request.