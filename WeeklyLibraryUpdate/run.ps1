<#
    .SYNOPSIS
        Export Spotify user library to a .csv file on Azure Blob Storage
    .DESCRIPTION
        Export Spotify user library to .csv file using the Spotify web API with OAuth2 Client Authorization flow
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

# Azure Key Vault name
$KeyVaultName = 'rylanddegregory'
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
#endregion Functions

#region GetLibrary
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
    Write-Host "[INFO] Processing Library for Spotify user $($User.display_name)"
} catch {
    throw "[ERROR] Error getting the authenticated user's Spotify profile: $($Error[0])"
}
# Determine the user's number of saved tracks and calculate the number of paginated requests to make
try {
    $LibraryTotal = Invoke-RestMethod -Method Get -Headers $Headers -Uri 'https://api.spotify.com/v1/me/tracks'
} catch {
    throw "[ERROR] Error getting the number of saved tracks for user: $($Error[0])"
}
$LibraryPages = [math]::ceiling($LibraryTotal.total / 50)

# Build collection of saved tracks by processing all pages
$UserLibrary = for ($i = 0; $i -lt $LibraryPages; $i++) {
    try {
        Invoke-RestMethod -Method Get -Headers $Headers -Uri "https://api.spotify.com/v1/me/tracks?limit=50&offset=$($i * 50)"
    } catch {
        throw "[ERROR] Error getting list of saved tracks for user: $($Error[0])"
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
    }
}
#endregion ProcessLibrary

#region Output
# Export collection of saved tracks to .csv format
$Csv = $TrackArray | ConvertTo-Csv -NoTypeInformation

# Upload .csv data to Azure Blob Storage
Push-OutputBinding -Name OutputBlob -Value ($Csv -join "`n")
#endregion Output