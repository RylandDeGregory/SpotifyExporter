<#
    .SYNOPSIS
        Export Spotify followed artists, library, and playlists weekly.
    .DESCRIPTION
        Fetch the three Spotify datasets in parallel, then export each dataset to Azure Blob Storage and Cosmos DB.
#>
param ($Timer)
$ErrorActionPreference = 'Stop'

$Headers = Get-SpotifyAccessToken
$UserBaseUrl = "${env:SPOTIFY_API_URL}/me"
$User = Invoke-RestMethod -Method Get -Headers $Headers -Uri $UserBaseUrl
Write-Information "Process Spotify exports for user [$($User.display_name)]"

$Results = 'Following', 'Library', 'Playlist' | ForEach-Object -Parallel {
    $ErrorActionPreference = 'Stop'

    $UserBaseUrl = $using:UserBaseUrl
    $MaxItems    = 50
    $JobName     = $_
    $ApiHeaders  = $using:Headers
    $UserProfile = $using:User

    try {
        $Data = switch ($JobName) {
            'Following' {
                $Response = @{
                    artists = @{
                        next = "$UserBaseUrl/following?type=artist&limit=$MaxItems"
                    }
                }
                $Followed = while ($Response.artists.next) {
                    $Response = Invoke-RestMethod -Method Get -Headers $ApiHeaders -Uri $Response.artists.next
                    $Response.artists.items
                    Write-Verbose "Processed [$($Response.artists.items.count)/$($Response.artists.total)] followed artists"
                }

                foreach ($Artist in $Followed) {
                    [PSCustomObject]@{
                        Name      = $Artist.name
                        ArtistUrl = $Artist.external_urls.spotify
                        Genres    = $Artist.genres | Join-String -Separator ', '
                        Followers = $Artist.followers.total
                        id        = $Artist.id
                    }
                }
            }
            'Library' {
                $Response = @{
                    next = "$UserBaseUrl/tracks?limit=$MaxItems"
                }
                $Count = 0
                $UserLibrary = while ($Response.next) {
                    try {
                        $Response = Invoke-RestMethod -Method Get -Headers $ApiHeaders -Uri $Response.next
                        $Response.items
                        $Count += $Response.items.count
                        Write-Verbose "Processed [$Count/$($Response.total)] saved tracks"
                        if ($Count % 1000 -eq 0) {
                            Write-Information "Processed [$Count] tracks. Sleep 10 seconds to avoid rate limiting."
                            Start-Sleep -Seconds 10
                        }
                    } catch {
                        if ($_.Exception.Response.StatusCode -eq 500) {
                            Write-Warning 'Rate limit exceeded. Try again in 30 seconds'
                            Start-Sleep -Seconds 30
                        } else {
                            throw
                        }
                    }
                }

                foreach ($Track in $UserLibrary) {
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
            }
            'Playlist' {
                $Response = @{
                    next = "$UserBaseUrl/playlists?limit=$MaxItems"
                }
                $Playlists = while ($Response.next) {
                    $Response = Invoke-RestMethod -Method Get -Headers $ApiHeaders -Uri $Response.next
                    $Response.items
                }

                $ProcessPlaylists = switch ($env:PLAYLIST_TYPE) {
                    'User' { $Playlists | Where-Object { $_.owner.id -eq $UserProfile.id } }
                    'Followed' { $Playlists | Where-Object { $_.owner.id -ne $UserProfile.id } }
                    'All' { $Playlists }
                    default { $Playlists }
                }

                Write-Information "Processing [$($ProcessPlaylists.Count)] playlists"

                $PlaylistResults = $ProcessPlaylists | ForEach-Object -Parallel {
                    $ErrorActionPreference = 'Stop'
                    $Playlist = $_
                    $PlaylistApiHeaders = $using:ApiHeaders

                    try {
                        $Response = @{
                            next = "${env:SPOTIFY_API_URL}/playlists/$($Playlist.id)/tracks"
                        }
                        $PlaylistTracks = while ($Response.next) {
                            $Response = Invoke-RestMethod -Method Get -Headers $PlaylistApiHeaders -Uri $Response.next
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
                        }

                        [PSCustomObject]@{
                            Name      = $Playlist.name
                            Data      = @($PlaylistTracks)
                            Succeeded = $true
                            Error     = $null
                        }
                    } catch {
                        [PSCustomObject]@{
                            Name      = $Playlist.name
                            Data      = @()
                            Succeeded = $false
                            Error     = $_.Exception.Message
                        }
                    }
                } -ThrottleLimit 3

                $PlaylistFailures = @($PlaylistResults | Where-Object { -not $_.Succeeded })
                if ($PlaylistFailures.Count -gt 0) {
                    $PlaylistFailureSummary = $PlaylistFailures | ForEach-Object { "[$($_.Name)] $($_.Error)" }
                    throw "Playlist exports failed: $($PlaylistFailureSummary -join '; ')"
                }

                $PlaylistResults.Data
            }
        }

        [PSCustomObject]@{
            Name      = $JobName
            Data      = @($Data)
            Succeeded = $true
            Error     = $null
        }
    } catch {
        [PSCustomObject]@{
            Name      = $JobName
            Data      = @()
            Succeeded = $false
            Error     = $_.Exception.Message
        }
    }
} -ThrottleLimit 3

$Failures = @($Results | Where-Object { -not $_.Succeeded })
if ($Failures.Count -gt 0) {
    $FailureSummary = $Failures | ForEach-Object { "[$($_.Name)] $($_.Error)" }
    throw "Spotify export failed: $($FailureSummary -join '; ')"
}

foreach ($Result in $Results) {
    Write-Information "Export [$($Result.Data.Count)] [$($Result.Name)] records"

    if ($env:COSMOS_ENABLED -eq 'True') {
        Push-OutputBinding -Name "$($Result.Name)Documents" -Value $Result.Data
    }

    if ($env:STORAGE_ENABLED -eq 'True') {
        $Csv = $Result.Data | ConvertTo-Csv -NoTypeInformation
        Push-OutputBinding -Name "$($Result.Name)Blob" -Value ($Csv -join "`n")
    }
}