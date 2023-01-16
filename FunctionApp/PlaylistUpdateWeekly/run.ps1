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

# Properties that will be returned for each track
# https://developer.spotify.com/documentation/web-api/reference/#endpoint-get-playlists-tracks
$TrackFields = 'items(added_at,added_by.id,track(name,id,external_urls(spotify),artists(name,external_urls(spotify)),album(name,external_urls(spotify))))'
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
    # Determine the user's number of playlists and calculate the number of paginated requests to make
    $PlaylistCount = Invoke-RestMethod -Method Get -Headers $Headers -Uri "$SpotifyApiUrl/me/playlists?limit=1"
    $PlaylistPages = [math]::ceiling($PlaylistCount.total / 50)
    Write-Information "Library contains [$($PlaylistCount.total)] playlists"
} catch {
    Write-Error "Error getting the number of playlists for user [$UserDisplayName]: $_"
}

# Build collection of playlists by processing all pages
$Playlists = for ($i = 0; $i -lt $PlaylistPages; $i++) {
    try {
        Write-Verbose "Processing playlist page [$i/$PlaylistPages]" -Verbose
        Invoke-RestMethod -Method Get -Headers $Headers -Uri "$SpotifyApiUrl/me/playlists?limit=50&offset=$($i * 50)"
    } catch {
        Write-Error "Error getting list of playlists for user [$UserDisplayName]: $_"
    }
}

# Process playlist types based on type
$ProcessPlaylists = switch ($env:PLAYLIST_TYPE) {
    'User' { $Playlists.items | Where-Object { $_.owner.id -eq $User.id } }
    'Followed' { $Playlists.items | Where-Object { $_.owner.id -ne $User.id } }
    'All' { $Playlists.items }
    default { $Playlists.items }
}
Write-Information "Processing [$($ProcessPlaylists.Count)] [$($env:PLAYLIST_TYPE)] playlists"
#endregion GetPlaylists

#region ProcessPlaylists
$TrackArray = foreach ($Playlist in $ProcessPlaylists) {
    Write-Information "Processing playlist [$($Playlist.name)] with [$($Playlist.tracks.total)] tracks"
    # Calculate the number of paginated requests to make to get all tracks in the playlist
    $TrackPages = [math]::ceiling($Playlist.tracks.total / 100)

    # Build collection of tracks by processing all pages
    for ($i = 0; $i -lt $TrackPages; $i++) {
        try {
            Write-Verbose "Processing track page [$i/$TrackPages] in playlist [$($Playlist.name)]" -Verbose
            # Get all tracks in the playlist page, the API returns only the pre-defined fields
            $Tracks = Invoke-RestMethod -Method Get -Headers $Headers -Uri "$SpotifyApiUrl/playlists/$($Playlist.id)/tracks?limit=100&offset=$($i * 100)&fields=$TrackFields"
        } catch {
            Write-Error "Error getting tracks from playlist [$($Playlist.name)]: $_"
        }

        Write-Information "Create collection of output objects for [$($Playlist.tracks.total)] tracks in playlist [$($Playlist.name)]"
        foreach ($Track in $Tracks.items) {
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
    }
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