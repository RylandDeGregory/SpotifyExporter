# SpotifyExporter

This repo contains a set of PowerShell Azure Functions which export Spotify user data (playlists, user library) to .csv files in Azure Blob Storage.

## Spotify Web API Authorization

Users must obtain a Client ID and Client Secret by registering a [Spotify App](https://developer.spotify.com/documentation/general/guides/app-settings/), as well as an OAuth 2 refresh token using the [Authorization Code Flow](https://developer.spotify.com/documentation/general/guides/authorization-guide/#authorization-code-flow).

I have modified and re-hosted Spotify's example Node.js application that grants an OAuth 2 refresh token. Follow the instructions in my [SpotifyWebAPIAuth](https://github.com/RylandDeGregory/SpotifyWebAPIAuth) GitHub repo to both register a Spotify app and obtain an OAuth 2 refresh token that can access your user profile using the Spotify Web API.

## Implementation

This repo can be deployed directly to Azure as a PowerShell Function App. See [ryland.dev](https://ryland.dev/posts/spotify-exporter) for more information and a step-by-step guide.

If you run into any issues with this repo, or the process outlined in the blog post, please open an issue or pull request.

### A note on the CosmosDB functions

The PowerShell Azure Functions `WeeklyCosmosLibraryUpdate` and `WeeklyCosmosPlaylistUpdate` are configured to export Spotify user data to an [Azure CosmosDB](https://azure.microsoft.com/en-us/services/cosmos-db/) database utilizing the SQL (core) API. I have validated the efficacy of these functions in achieving their intended purpose, but I do not have them implemented in my Azure Subscription due to the cost of CosmosDB. Feel free to use them if you wish.