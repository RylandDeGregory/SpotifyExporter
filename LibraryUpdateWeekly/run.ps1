<#
    .SYNOPSIS
        Export Spotify user library
    .DESCRIPTION
        Export Spotify user library to one or both .csv file on Azure Blob Storage and CosmosDB NoSQL collection using the Spotify web API with OAuth2 Client Authorization flow
    .NOTES
        - Assumes that a Spotify application has been configured and an OAuth2 Refresh token has been granted for a user containing the 'user-library-read' and 'user-read-private' scopes
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

#region GetLibrary
try {
    $User = Invoke-RestMethod -Method Get -Headers $Headers -Uri "$SpotifyApiUrl/me/"
    $UserDisplayName = $User.display_name
    Write-Information "Process Library for Spotify user [$UserDisplayName]"
} catch {
    Write-Error "Error getting the authenticated user's Spotify profile: $_"
}

$Response = @{
    next = "$SpotifyApiUrl/me/tracks?limit=50"
}
$Count = 0
$UserLibrary = while ($Response.next) {
    try {
        $Response = Invoke-RestMethod -Method Get -Headers $Headers -Uri $Response.next
        $Response.items
        $Count += $Response.items.count
        Write-Verbose "Processed [$Count/$($Response.total)] saved tracks"
        if ($Count % 1000 -eq 0) {
            Write-Information "Processed [$Count] tracks. Sleep 10 seconds to avoid rate limiting."
            Start-Sleep -Seconds 10
        }
    } catch {
        if ($_.Exception.Response.StatusCode -eq 500) { # Should be 429 but Spotify returns 500 for this endpoint
            Write-Warning 'Rate limit exceeded. Try again in 30 seconds'
            Start-Sleep -Seconds 30
        } else {
            Write-Error "Error getting list of saved tracks for user [$UserDisplayName]: $_"
            break
        }
    }
}
#endregion GetLibrary

#region ProcessLibrary
Write-Information "Create collection of output objects for [$($UserLibrary.items.Count)] tracks in user Library"
$TrackArray = foreach ($Track in $UserLibrary.items) {
    [PSCustomObject]@{
        AddedAt   = $Track.added_at
        Name      = $Track.track.name
        TrackURL  = $Track.track.external_urls.spotify
        Artist    = $Track.track.artists.name | Join-String -Separator ', '
        ArtistURL = $Track.track.artists.external_urls.spotify | Join-String -Separator ', '
        Album     = $Track.track.album.name
        AlbumURL  = $Track.track.album.external_urls.spotify
        id        = $Track.track.id
    }
}
#endregion ProcessLibrary

#region Output
if ($env:COSMOS_ENABLED -eq 'True') {
    Write-Information 'Export collection of objects to CosmosDB'
    Push-OutputBinding -Name OutputDocument -Value $TrackArray
}

if ($env:STORAGE_ENABLED -eq 'True') {
    Write-Information 'Convert output collection of objects to CSV'
    $Csv = $TrackArray | ConvertTo-Csv -NoTypeInformation

    Write-Information 'Upload CSV to Azure Storage'
    Push-OutputBinding -Name OutputBlob -Value ($Csv -join "`n")
}
#endregion Output