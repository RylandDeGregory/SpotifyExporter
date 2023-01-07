<#
    .SYNOPSIS
        Export Spotify user playback history to a .csv file on Azure Blob Storage
    .DESCRIPTION
        Export Spotify user playback history to .csv file using the Spotify web API with OAuth2 Client Authorization flow
    .NOTES
        - Assumes that a Spotify application has been configured and an OAuth2 Refresh token has been granted for a user
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

#region GetPlaybackHistory
try {
    $User = Invoke-RestMethod -Method Get -Headers $Headers -Uri "$SpotifyApiUrl/me/"
    $UserDisplayName = $User.display_name
    Write-Information "Process playback history for Spotify user [$UserDisplayName]"
} catch {
    Write-Error "Error getting the authenticated user's Spotify profile: $_"
}

try {
    # Get the user's 50 most recently played tracks (50 is an API limitation, which requires higher polling to ensure nothing is missed)
    Write-Information 'Process 50 most recently played tracks'
    $RecentlyPlayed = Invoke-RestMethod -Method Get -Headers $Headers -Uri "$SpotifyApiUrl/me/player/recently-played?limit=50"
} catch {
    Write-Error "Error getting recently played tracks for user [$UserDisplayName]: $_"
}

#endregion GetLibrary

#region ProcessLibrary
Write-Information "Create collection of output objects for [$($RecentlyPlayed.items.Count)] tracks in user playback history"
$TrackArray = foreach ($Track in $RecentlyPlayed.items) {
    [PSCustomObject]@{
        PlayedAt  = $Track.played_at
        Name      = $Track.track.name
        TrackURL  = $Track.track.external_urls.spotify
        Artist    = $Track.track.artists.name | Join-String -Separator ', '
        ArtistURL = $Track.track.artists.external_urls.spotify | Join-String -Separator ', '
        Album     = $Track.track.album.name
        AlbumURL  = $Track.track.album.external_urls.spotify
    }
}
#endregion ProcessLibrary

#region Output
Write-Information 'Convert output collection of objects to CSV'
$Csv = $TrackArray | ConvertTo-Csv -NoTypeInformation

Write-Information 'Upload CSV to Azure Storage'
Push-OutputBinding -Name OutputBlob -Value ($Csv -join "`n")
#endregion Output