# SpotifyExporter

This repo contains a set of PowerShell Azure Functions which export Spotify user data (playlists, user library) to .csv files on Azure Blob Storage.

## Authorization
Users must obtain an OAuth 2 Refresh token using the [Authorization Code Flow](https://developer.spotify.com/documentation/general/guides/authorization-guide/#authorization-code-flow), as well as a Client ID and Client Secret by creating a [Spotify Application](https://developer.spotify.com/documentation/general/guides/app-settings/).

I have modified and re-hosted Spofity's example Node.js application that grants an OAuth 2 Refresh token. Follow the instructions in the [SpotifyWebAPIAuth](https://github.com/RylandDeGregory/SpotifyWebAPIAuth) `README.md` to both create an Application and obtain an OAuth 2 Refresh token that can access the Spotify API for your user account.

See https://ryland.dev for more information.


#### A note on the CosmosDB functions

The PowerShell Azure Functions `WeeklyCosmosLibraryUpdate` and `WeeklyCosmosPlaylistUpdate` are configured to export Spotify user data to a CosmosDB database utilizing the SQL (core) API. I have validated the efficacy of these functions in achieving their intended purpose, but I do not have them implemented due to the cost of Cosmos DB. Feel freel to use them as you wish, and if you run into any issues, please open an issue or PR.
