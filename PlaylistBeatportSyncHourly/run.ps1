<#
    .SYNOPSIS
        Synchronize a Spotify playlist to a Beatport playlist
    .DESCRIPTION
        Synchronize a Spotify playlist to a Beatport playlist. Utilizes the Spotify Web API and the Beatport Web API
        Synchronization is a best-effort process using the Beatport Catalog API
        If multiple tracks are returned from a Beatport query, the first result is added to the playlist
    .NOTES
        - Assumes that a Spotify application has been configured and an OAuth2 Refresh token has been granted for a user
          https://developer.spotify.com/documentation/general/guides/authorization-guide/
        - Assumes that a Beatport OAuth2 Refresh token has been granted for a user
          See the repository's README.md file for more information
    .LINK
        https://ryland.dev
#>
#region Init
param ($Timer)
$ErrorActionPreference = 'Stop'

# Spotify API config
$SpotifyApiUrl = 'https://api.spotify.com/v1'
$SpotifyHeaders = Get-SpotifyAccessToken

# Beatport API config
$BeatportApiUrl       = 'https://api.beatport.com/v4'
$BeatportAccessToken  = Get-AzKeyVaultSecret -VaultName $env:KEY_VAULT_NAME -SecretName 'Beatport-AccessToken' -AsPlainText
$BeatportRefreshToken = Get-AzKeyVaultSecret -VaultName $env:KEY_VAULT_NAME -SecretName 'Beatport-RefreshToken' -AsPlainText
$BeatportHeaders      = Get-BeatportAccessToken -AccessToken $BeatportAccessToken -RefreshToken $BeatportRefreshToken
$BeatportPostHeaders  = $BeatportHeaders += @{ 'Accept' = 'application/json' }
#endregion Init

#region GetSpotifyPlaylist
try {
    # Get the Spotify user's list of playlists
    $Response = @{
        next = "$SpotifyApiUrl/me/playlists?limit=50"
    }
    $SpotifyPlaylists = while ($Response.next) {
        $Response = Invoke-RestMethod -Method Get -Headers $SpotifyHeaders -Uri $Response.next
        $Response.items
    }
} catch {
    Write-Error "Error getting list of Spotify playlists for user: $_"
}

# Get the target playlist by name
$SpotifyPlaylist = $SpotifyPlaylists | Where-Object { $_.Name -eq $env:SYNCED_PLAYLIST_NAME }
if (-not $SpotifyPlaylist) {
    Write-Error "User [$($User.display_name) ($($User.id))] does not have a playlist named [$($env:SYNCED_PLAYLIST_NAME)]"
}
#endregion GetSpotifyPlaylist

#region GetBeatportPlaylist
try {
    $BeatportPlaylists = Invoke-RestMethod -Method Get "$BeatportApiUrl/my/playlists/" -Body @{ 'per_page' = 100 } -Headers $BeatportHeaders -ContentType 'application/x-www-form-urlencoded'
} catch {
    Write-Error "Error getting list of Beatport playlists for user: $_"
}
$BeatportPlaylist = $BeatportPlaylists.results | Where-Object { $_.Name -eq $env:SYNCED_PLAYLIST_NAME }
#endregion GetBeatportPlaylist

#region ProcessSpotifyPlaylist
Write-Output "Processing playlist [$($SpotifyPlaylist.name)] with [$($SpotifyPlaylist.tracks.total)] tracks [$PlaylistCount/$($ProcessPlaylists.Count)]"
try {
    # Get all tracks in the playlist
    $Response = @{
        next = "$SpotifyApiUrl/playlists/$($SpotifyPlaylist.id)/tracks"
    }
    $TrackArray = while ($Response.next) {
        $Response = Invoke-RestMethod -Method Get -Headers $SpotifyHeaders -Uri $Response.next
        foreach ($Track in $Response.items) {
            [PSCustomObject]@{
                Name   = $Track.track.name
                Artist = $Track.track.artists.name | Select-Object -First 1
            }
        }
    }
} catch {
    Write-Error "Error getting list of tracks in Playlist [$($SpotifyPlaylist.name)]: $_"
}
#endregion ProcessSpotifyPlaylist

#region ProcessBeatportPlaylist
try {
    # Get all tracks in the playlist
    $Response = @{
        next = "$BeatportApiUrl/my/playlists/$($BeatportPlaylist.id)/tracks/"
    }
    $BeatportPlaylistTracks = while ($Response.next) {
        $Response = Invoke-RestMethod -Method Get -Headers $BeatportHeaders -Uri $Response.next
        foreach ($Track in $Response.results) {
            [PSCustomObject]@{
                Id     = $Track.track.id
                Name   = $Track.track.name
                Artist = $Track.track.artists.name | Join-String -Separator ', '
            }
        }
    }
} catch {
    Write-Error "Error getting list of tracks in Playlist [$($BeatportPlaylist.name)]: $_"
}
#endregion ProcessBeatportPlaylist

#region SyncBeatportPlaylist
foreach ($Track in $TrackArray) {
    Write-Output "[$($Track.Name)] by [$($Track.Artist)]"
    switch -Wildcard ($Track.Name) {
        '*- Extended Mix' { $MixName = 'Extended Mix'; $TrackName = $Track.Name.Split(' - ')[0] }
        '*- Original Mix' { $MixName = 'Original Mix'; $TrackName = $Track.Name.Split(' - ')[0] }
        '*-* Remix' { $MixName = $Track.Name.Split(' - ')[1]; $TrackName = $Track.Name.Split(' - ')[0] }
        default { $MixName = 'Original Mix'; $TrackName = $Track.Name }
    }
    $BeatportTrackUrl = "$BeatportApiUrl/catalog/tracks/?name=$TrackName&artist_name=$($Track.Artist)&mix_name=$MixName"
    $BeatportSearchUrl = "$BeatportApiUrl/catalog/search/?type=tracks&q=$TrackName&artist_name=$($Track.Artist)&mix_name=$MixName"
    Write-Verbose "Beatport track search URL: $BeatportTrackUrl" -Verbose
    Write-Verbose "Beatport catalog search URL: $BeatportSearchUrl" -Verbose

    try {
        Write-Output "Search Beatport tracks API for track with artist [$($Track.Artist)] name [$($TrackName)] and mix [$MixName]"
        $BeatportTrackResults = Invoke-RestMethod -Method Get $BeatportTrackUrl -Headers $BeatportHeaders
    } catch {
        Write-Error "Error getting Beatport track with artist [$($Track.Artist)] name [$($TrackName)] and mix [$MixName]: $_"
    }

    if ($BeatportTrackResults.count -eq 1) {
        $BeatportTrack = $BeatportTrackResults.results
    } elseif ($BeatportTrackResults.count -gt 1) {
        Write-Warning "[$($BeatportTrackResults.count)] results returned from search. Selecting first result as track to add."
        $BeatportTrack = $BeatportTrackResults.results[0]
    } else {
        $BeatportTrack = $null
        Write-Warning "No results from Tracks API"
    }

    if ($BeatportTrackResults.count -eq 0) {
        try {
            Write-Output "Search Beatport catalog API for track with artist [$($Track.Artist)] name [$($TrackName)] and mix [$MixName]"
            $BeatportCatalogResults = Invoke-RestMethod -Method Get $BeatportSearchUrl -Headers $BeatportHeaders

            if ($BeatportCatalogResults.count -eq 1) {
                $BeatportTrack = $BeatportCatalogResults.tracks
            } elseif ($BeatportCatalogResults.count -gt 1) {
                Write-Warning "[$($BeatportCatalogResults.count)] results returned from search. Selecting first result as track to add."
                $BeatportTrack = $BeatportCatalogResults.tracks[0]
            } else {
                $BeatportTrack = $null
                Write-Warning "No results from Catalog API"
                continue
            }
        } catch {
            Write-Error "Error searching for Beatport track with artist [$($Track.Artist)] name [$($TrackName)] and mix [$MixName]: $_"
        }
    }

    if ($BeatportTrack.id -notin $BeatportPlaylistTracks.Id) {
        Write-Output "Adding track [$($BeatportTrack.name)] by [$($BeatportTrack.artists.name)] with ID [$($BeatportTrack.id)] to Beatport Playlist [$($BeatportPlaylist.name)]"
        $RequestParams = @{
            Method      = 'Post'
            Uri         = "$BeatportApiUrl/my/playlists/$($BeatportPlaylist.id)/tracks/"
            Headers     = $BeatportPostHeaders
            Body        = (@{ 'track_id' = $BeatportTrack.id } | ConvertTo-Json)
            ContentType = 'application/json'
        }
        Invoke-RestMethod @RequestParams | Out-Null
    } else {
        Write-Output "Track [$($BeatportTrack.name)] by [$($BeatportTrack.artists.name)] with ID [$($BeatportTrack.id)] is already in Beatport Playlist [$($BeatportPlaylist.name)]"
    }
}
#endregion SyncBeatportPlaylist