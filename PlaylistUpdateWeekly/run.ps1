<#
    .SYNOPSIS
        Export Spotify playlists
    .DESCRIPTION
        Export Spotify playlists to one or both .csv file on Azure Blob Storage and CosmosDB NoSQL collection using the Spotify web API with OAuth2 Client Authorization flow
    .NOTES
        - Assumes that a Spotify application has been configured and an OAuth2 Refresh token has been granted for a user containing the 'playlist-read-collaborative' and 'playlist-read-private' scopes
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

#region GetPlaylists
try {
    $User = Invoke-RestMethod -Method Get -Headers $Headers -Uri "$SpotifyApiUrl/me/"
    $UserDisplayName = $User.display_name
    Write-Information "Process Library for Spotify user [$UserDisplayName]"
} catch {
    Write-Error "Error getting the authenticated user's Spotify profile: $_"
}

try {
    # Get the user's list of playlists
    $Response = @{
        next = "$SpotifyApiUrl/me/playlists?limit=50"
    }
    $Count = 0
    $Playlists = while ($Response.next) {
        $Response = Invoke-RestMethod -Method Get -Headers $Headers -Uri $Response.next
        $Response.items
        $Count += $Response.items.count
        Write-Verbose "Processed [$Count/$($Response.total)] playlists"
    }
} catch {
    Write-Error "Error getting list of playlists for user [$UserDisplayName]: $_"
}

# Process playlist types based on App Setting
$ProcessPlaylists = switch ($env:PLAYLIST_TYPE) {
    'User' { $Playlists | Where-Object { $_.owner.id -eq $User.id } }
    'Followed' { $Playlists | Where-Object { $_.owner.id -ne $User.id } }
    'All' { $Playlists }
    default { $Playlists }
}
Write-Information "Processing [$($ProcessPlaylists.Count)] [$($env:PLAYLIST_TYPE)] playlists"
#endregion GetPlaylists

#region ProcessPlaylists
$PlaylistCount = 1
$TrackArray = foreach ($Playlist in $ProcessPlaylists) {
    Write-Information "Processing playlist [$($Playlist.name)] with [$($Playlist.tracks.total)] tracks [$PlaylistCount/$($ProcessPlaylists.Count)]"
    try {
        # Get the user's list of playlists
        $Response = @{
            next = "$SpotifyApiUrl/playlists/$($Playlist.id)/tracks"
        }
        $Count = 0
        while ($Response.next) {
            $Response = Invoke-RestMethod -Method Get -Headers $Headers -Uri $Response.next
            foreach ($Track in $Response.items) {
                [PSCustomObject]@{
                    PlaylistName  = $Playlist.name -replace '[^a-zA-Z0-9 -]', ''
                    PlaylistOwner = $Playlist.owner.id
                    PlaylistURL   = $Playlist.external_urls.spotify
                    AddedAt       = $Track.added_at
                    AddedBy       = $Track.added_by.id
                    Name          = $Track.track.name
                    TrackURL      = $Track.track.external_urls.spotify
                    Artist        = $Track.track.artists.name | Join-String -Separator ', '
                    ArtistURL     = $Track.track.artists.external_urls.spotify | Join-String -Separator ', '
                    Album         = $Track.track.album.name
                    AlbumURL      = $Track.track.album.external_urls.spotify
                    id            = "$($Playlist.id)_$($Track.track.id)"
                }
            }
            $Count += $Response.items.count
            Write-Verbose "Processed [$Count/$($Response.total)] tracks in Playlist [$($Playlist.name)]"
        }
    } catch {
        Write-Error "Error getting list of tracks in Playlist [$($Playlist.name)]: $_"
    }
    $PlaylistCount++
}
#endregion ProcessPlaylists

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