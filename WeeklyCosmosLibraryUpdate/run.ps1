<#
    .SYNOPSIS
        Export Spotify user library to an Azure CosmosDB collection
    .DESCRIPTION
        Export Spotify user library to an Azure CosmosDB using the Spotify web API with OAuth2 Client Authorization flow
    .NOTES
        - Assumes that a Spotify application has been configured and an OAuth2 Refresh token has been granted for a user
          https://developer.spotify.com/documentation/general/guides/authorization-guide/
        - Assumes that an Azure Key Vault has been configured to store Spotify API secrets
          https://docs.microsoft.com/en-us/azure/key-vault/secrets/quick-create-portal
    .LINK
        https://ryland.dev
#>
#region Init
param ($Timer)

# Ensure Function stops if an error is encountered
$ErrorActionPreference = 'Stop'

# Set Application credentials from Application Settings
$ApplicationCredentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($env:SPOTIFY_CLIENT_ID)`:$($env:SPOTIFY_CLIENT_SECRET)"))
#endregion Init

#region GetAccessToken
# Set Request elements
$TokenHeader = @{ 'Authorization' = "Basic $ApplicationCredentials" }
$TokenBody   = @{ grant_type = 'refresh_token'; refresh_token = "$($env:SPOTIFY_REFRESH_TOKEN)" }
try {
    # Get an Access token from the Refresh token
    $AccessToken = Invoke-RestMethod -Method Post -Headers $TokenHeader -Uri 'https://accounts.spotify.com/api/token' -Body $TokenBody | Select-Object -ExpandProperty access_token
} catch {
    Write-Error "[ERROR] Error getting Access Token from Spotify API '/token' endpoint using Refresh Token: $_"
}

# Get OAuth2 Access token and set API headers
if ($AccessToken) {
    $Headers = @{ 'Authorization' = "Bearer $AccessToken" }
} else {
    Write-Error '[ERROR] No OAuth2 Access token was granted. Please ensure that the application ClientID and ClientSecret, and the user OAuth2 Refresh token are valid.'
}
#endregion GetAccessToken

#region GetLibrary
try {
    # Get the authenticated user's Spotify profile
    $User = Invoke-RestMethod -Method Get -Headers $Headers -Uri 'https://api.spotify.com/v1/me/'
    Write-Host "[INFO] Processing Library for Spotify user $($User.display_name)"
} catch {
    Write-Error "[ERROR] Error getting the authenticated user's Spotify profile: $_"
}
# Determine the user's number of saved tracks and calculate the number of paginated requests to make
try {
    $LibraryTotal = Invoke-RestMethod -Method Get -Headers $Headers -Uri 'https://api.spotify.com/v1/me/tracks'
} catch {
    Write-Error "[ERROR] Error getting the number of saved tracks for user: $_"
}
$LibraryPages = [math]::ceiling($LibraryTotal.total / 50)

# Build collection of saved tracks by processing all pages
$UserLibrary = for ($i = 0; $i -lt $LibraryPages; $i++) {
    try {
        Invoke-RestMethod -Method Get -Headers $Headers -Uri "https://api.spotify.com/v1/me/tracks?limit=50&offset=$($i * 50)"
    } catch {
        Write-Error "[ERROR] Error getting list of saved tracks for user: $_"
    }
}
#endregion GetLibrary

#region ProcessLibrary
# Create object for each track in library with processed data
$TrackArray = foreach ($Track in $UserLibrary.items) {
    [PSCustomObject]@{
        AddedAt      = $Track.added_at
        Name         = $Track.track.name
        TrackURL     = $Track.track.external_urls.spotify
        Artist       = $Track.track.artists.name | Join-String -Separator ', '
        ArtistURL    = $Track.track.artists.external_urls.spotify | Join-String -Separator ', '
        Album        = $Track.track.album.name
        AlbumURL     = $Track.track.album.external_urls.spotify
        id           = $Track.track.id
    }
}
#endregion ProcessLibrary

#region Output
Push-OutputBinding -Name OutputDocument -Value $TrackArray
#endregion Output