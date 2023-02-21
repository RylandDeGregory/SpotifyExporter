<#
    .SYNOPSIS
        Export Spotify user followed artists
    .DESCRIPTION
        Export Spotify user followed artists to one or both .csv file on Azure Blob Storage and CosmosDB NoSQL collection using the Spotify web API with OAuth2 Client Authorization flow
    .NOTES
        - Assumes that a Spotify application has been configured and an OAuth2 Refresh token has been granted for a user containing the 'user-follow-read' and 'user-read-private' scopes
          https://developer.spotify.com/documentation/general/guides/authorization-guide/
    .LINK
        https://ryland.dev
#>
#region Init
param ($Timer)
$ErrorActionPreference = 'Stop'

# Spotify API config
$SpotifyApiUrl = 'https://api.spotify.com/v1'
$Headers = Get-SpotifyAccessToken
#endregion Init

#region GetFollowed
try {
    $User = Invoke-RestMethod -Method Get -Headers $Headers -Uri "$SpotifyApiUrl/me/"
    $UserDisplayName = $User.display_name
    Write-Information "Process followed artists for Spotify user [$UserDisplayName]"
} catch {
    Write-Error "Error getting the authenticated user's Spotify profile: $_"
}

try {
    # Get the user's list of followed artists
    $Response = @{
        artists = @{
            next = "$SpotifyApiUrl/me/following?type=artist&limit=50"
        }
    }
    $Followed = while ($Response.artists.next) {
        $Response = Invoke-RestMethod -Method Get -Headers $Headers -Uri $Response.artists.next
        $Response.artists.items
    }
} catch {
    Write-Error "Error getting list of followed artists for user [$UserDisplayName]: $_"
}
#endregion GetFollowed

#region ProcessFollowed
Write-Information "Create collection of output objects for [$($Followed.items.Count)] followed artists"
$ArtistArray = foreach ($Artist in $Followed) {
    [PSCustomObject]@{
        Name      = $Artist.name
        ArtistUrl = $Artist.external_urls.spotify
        Genres    = $Artist.genres | Join-String -Separator ', '
        Followers = $Artist.followers.total
        id        = $Artist.id
    }
}
#endregion ProcessFollowed

#region Output
if ($env:COSMOS_ENABLED -eq 'True') {
    Write-Information 'Export collection of objects to CosmosDB'
    Push-OutputBinding -Name OutputDocument -Value $ArtistArray
}

if ($env:STORAGE_ENABLED -eq 'True') {
    Write-Information 'Convert output collection of objects to CSV'
    $Csv = $ArtistArray | ConvertTo-Csv -NoTypeInformation

    Write-Information 'Upload CSV to Azure Storage'
    Push-OutputBinding -Name OutputBlob -Value ($Csv -join "`n")
}
#endregion Output