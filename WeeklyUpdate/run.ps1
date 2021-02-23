<#
    .SYNOPSIS
        Export Spotify playlists to .csv file for backup
    .DESCRIPTION
        Export Spotify playlists to .csv file using the Spotify web API with OAuth2 Client Authorization flow
    .EXAMPLE
        ./Start-SpotifyPlaylistExport.ps1 -KeyVaultName 'myazkeyvault' -PlaylistType 'User'
    .NOTES
        - Assumes that a Spotify application has been configured and an OAuth2 Refresh token has been granted for a user
          https://developer.spotify.com/documentation/general/guides/authorization-guide/
        - Assumes that an Azure Key Vault has been configured to store API secrets
          https://docs.microsoft.com/en-us/azure/key-vault/secrets/quick-create-portal
    .LINK
        https://ryland.dev
#>
#region Init
param ($Timer)

# Properties that will be returned for each track
# https://developer.spotify.com/documentation/web-api/reference/#endpoint-get-playlists-tracks
$TrackFields = 'items(added_at,added_by.id,track(name,id,external_urls(spotify),artists(name,external_urls(spotify)),album(name,external_urls(spotify))))'

# File system location for the resulting .csv file containing playlist data
$OutputFileLocation = "$HOME/Desktop/PlaylistExport_$(Get-Date -Format 'yyyy-MM-dd').csv"

$KeyVaultName = 'rylanddegregory'
$PlaylistType = 'User'
#endregion Init

#region Functions
function Get-SpotifyAccessToken {
    <#
        .SYNOPSIS
            Get an OAuth2 Access token from an OAuth2 Refresh token and an application Client ID and Client Secret
            OAuth2 Access token is used to access the Spotify API
    #>
    [CmdletBinding()]
    param (
        # The name of the Azure Key Vault where Spotify API secrets are stored
        [Parameter(Mandatory)]
        [string] $KeyVaultName
    )

    begin {
        # Application credentials
        $ClientId               = Get-AzKeyVaultSecret -VaultName $KeyVaultName -SecretName 'Spotify-ClientID' -AsPlainText
        $ClientSecret           = Get-AzKeyVaultSecret -VaultName $KeyVaultName -SecretName 'Spotify-ClientSecret' -AsPlainText
        $ApplicationCredentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$ClientId`:$ClientSecret"))

        # User credentials
        $RefreshToken = Get-AzKeyVaultSecret -VaultName $KeyVaultName -SecretName 'Spotify-RefreshToken' -AsPlainText
    }

    process {
        # Request elements
        $TokenHeader = @{ 'Authorization' = "Basic $ApplicationCredentials" }
        $TokenBody   = @{ grant_type = 'refresh_token'; refresh_token = "$RefreshToken" }
        try {
            # Get an Access token from the Refresh token
            $AccessToken = Invoke-RestMethod -Method Post -Headers $TokenHeader -Uri 'https://accounts.spotify.com/api/token' -Body $TokenBody
        } catch {
            throw "[ERROR] Error getting Access Token from Spotify API '/token' endpoint using Refresh Token: $($Error[0])"
        }
    }

    end {
        # If an Access token was granted, return it
        if ($AccessToken) {
            return $AccessToken.access_token
       } else {
           return $null
       }
    }
} #endfunction Get-SpotifyAccessToken
function New-AzStorageReport {
    <#
        .SYNOPSIS
            Copy a report file from a local temp directory to an Azure Storage Account
    #>
    [CmdletBinding()]
    param (
        # Fully-qualified filesystem path to the file being uploaded to Azure Storage
        [Parameter(Mandatory)]
        [string]$ReportDirectory
    )

    begin {
        Write-Verbose '[INFO] Entering New-AzStorageReport'
        $File = Split-Path $ReportDirectory -Leaf
    }

    process {
        try {
            # Storage Account variables
            $StorageAccountRG   = 'blog'
            $StorageAccountName = 'rylanddegregory'
            $Container          = 'spotify'

            # Set Azure Storage Context
            $ContextParams = @{
                StorageAccountName = $StorageAccountName
                StorageAccountKey  = $(Get-AzStorageAccountKey -ResourceGroupName $StorageAccountRG -Name $StorageAccountName)[0].Value
            }
            $StorageAccountContext = New-AzStorageContext @ContextParams
        } catch {
            throw "[ERROR] Error setting Azure Storage Context to [$StorageAccountName]: $($Error[0])"
        }
        try {
            # Upload file to Azure Blob Storage
            $Params = @{
                Context   = $StorageAccountContext
                Container = $Container
                File      = $ReportDirectory
                Blob      = "PlaylistExport/$File"
            }
            Set-AzStorageBlobContent @Params -Force
        } catch {
            throw "[ERROR] Error Uploading [$File] to Azure Storage: $($Error[0])"
        }
    }

    end {
        Write-Output "[INFO] Uploaded [$File] to Azure Storage"
    }
} #endfunction New-AzStorageReport

#endregion Functions

#region GetPlaylists
# Get OAuth2 Access token and set API headers
$AccessToken = Get-SpotifyAccessToken -KeyVaultName $KeyVaultName
if ($AccessToken) {
    $Headers = @{ 'Authorization' = "Bearer $AccessToken" }
} else {
    throw '[ERROR] No OAuth2 Access token was granted. Please ensure that the application ClientID and ClientSecret, and the user OAuth2 Refresh token are valid.'
}

try {
    # Get the authenticated user's Spotify profile
    $User = Invoke-RestMethod -Method Get -Headers $Headers -Uri 'https://api.spotify.com/v1/me/'
    Write-Verbose "[INFO] Processing playlists for Spotify user $($User.display_name)"
} catch {
    throw "[ERROR] Error getting the authenticated user's Spotify profile: $($Error[0])"
}
# Determine the user's number of playlists and calculate the number of paginated requests to make
try {
    $PlaylistCount = Invoke-RestMethod -Method Get -Headers $Headers -Uri 'https://api.spotify.com/v1/me/playlists?limit=1'
} catch {
    throw "[ERROR] Error getting the number of playlists for user: $($Error[0])"
}
$PlaylistPages = [math]::ceiling($PlaylistCount.total / 50)

# Build collection of playlists by processing all pages
$Playlists = for ($i = 0; $i -lt $PlaylistPages; $i++) {
    try {
        Invoke-RestMethod -Method Get -Headers $Headers -Uri "https://api.spotify.com/v1/me/playlists?limit=50&offset=$($i * 50)"
    } catch {
        throw "[ERROR] Error getting list of playlists for user: $($Error[0])"
    }
}

# Process playlist types based on parameter input
$ProcessPlaylists = switch ($PlaylistType) {
    'User' { $Playlists.items | Where-Object { $_.owner.id -eq $User.id } }
    'Followed' { $Playlists.items | Where-Object { $_.owner.id -ne $User.id } }
    'All' { $Playlists.items }
}
#endregion GetPlaylists

#region ProcessPlaylists
$TrackArray = foreach ($Playlist in $ProcessPlaylists) {
    Write-Verbose "[INFO] Processing playlist [$($Playlist.name)]"
    # Calculate the number of paginated requests to make to get all tracks in the playlist
    $TrackPages = [math]::ceiling($Playlist.tracks.total / 100)

    # Build collection of tracks by processing all pages
    for ($i = 0; $i -lt $TrackPages; $i++) {
        try {
            # Get all tracks in the playlist page, the API returns only the pre-defined fields
            $Tracks = Invoke-RestMethod -Method Get -Headers $Headers -Uri "https://api.spotify.com/v1/playlists/$($Playlist.id)/tracks?limit=100&offset=$($i * 100)&fields=$TrackFields"
        } catch {
            throw "[ERROR] Error getting tracks from playlist [$($Playlist.name)]: $($Error[0])"
        }

        # Create object for each track in playlist with processed data
        foreach ($Track in $Tracks.items) {
            [PSCustomObject]@{
                PlaylistName = $Playlist.name -replace '[^a-zA-Z0-9 ]', ''
                PlaylistURL  = $Playlist.external_urls.spotify
                AddedAt      = $Track.added_at
                AddedBy      = $Track.added_by.id
                Name         = $Track.track.name
                TrackURL     = $Track.track.external_urls.spotify
                Artist       = $Track.track.artists.name | Join-String -Separator ', '
                ArtistURL    = $Track.track.artists.external_urls.spotify | Join-String -Separator ', '
                Album        = $Track.track.album.name
                AlbumURL     = $Track.track.album.external_urls.spotify
            }
        }
    }
}
#endregion ProcessPlaylists

#region Output
# Export collection of tracks from all processed playlists to a .csv file at the pre-defined path
$TrackArray | Export-Csv -Path $OutputFileLocation -NoTypeInformation -Force
#endregion Output