# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.
function Get-SpotifyAccessToken {
    [CmdletBinding()]
    param ()

    # Set Application credentials from Application Settings
    $ApplicationCredentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($env:SPOTIFY_CLIENT_ID)`:$($env:SPOTIFY_CLIENT_SECRET)"))

    # Set Request elements
    $TokenHeader = @{ 'Authorization' = "Basic $ApplicationCredentials" }
    $TokenBody   = @{ grant_type = 'refresh_token'; refresh_token = "$($env:SPOTIFY_REFRESH_TOKEN)" }

    try {
        # Get an Access token from the Refresh token
        $AccessToken = Invoke-RestMethod -Method Post -Headers $TokenHeader -Uri 'https://accounts.spotify.com/api/token' -Body $TokenBody | Select-Object -ExpandProperty access_token
    } catch {
        Write-Error "Error getting Access Token from Spotify API '/token' endpoint using Refresh Token: $_"
    }

    # Get OAuth2 Access token and set API headers
    if ($AccessToken) {
        $ApiHeaders = @{ 'Authorization' = "Bearer $AccessToken" }
    } else {
        Write-Error 'No OAuth2 Access token was granted. Please ensure that the application ClientID and ClientSecret, and the user OAuth2 Refresh token are valid.'
    }
    return $ApiHeaders
}

function Get-BeatportAccessToken {
    [CmdletBinding()]
    param (
        # Beatport OAuth 2 Access Token
        [Parameter(Mandatory)]
        [string] $AccessToken,

        # Beatport OAuth 2 Refresh Token
        [Parameter(Mandatory)]
        [string] $RefreshToken
    )

    # Set Request elements
    $TokenHeader = @{ 'Authorization' = "Bearer $AccessToken" }
    $TokenBody   = @{ client_id = $env:BEATPORT_CLIENT_ID; grant_type = 'refresh_token'; refresh_token = $RefreshToken }

    try {
        # Get an Access token from the Refresh token
        $TokenResponse = Invoke-WebRequest -Method Post -Headers $TokenHeader -Uri 'https://api.beatport.com/v4/auth/o/token/' -Body $TokenBody -ContentType 'application/x-www-form-urlencoded'
        $NewAccessToken = $TokenResponse.Content | ConvertFrom-Json | Select-Object -ExpandProperty access_token
        $NewRefreshToken = $TokenResponse.Content | ConvertFrom-Json | Select-Object -ExpandProperty refresh_token
    } catch {
        Write-Error "Error getting updated Access Token from Beatport API '/auth/o/token/' endpoint using Refresh Token: $_"
    }

    # Get OAuth2 Access token and set API headers
    if ($NewAccessToken) {
        $ApiHeaders = @{ 'Authorization' = "Bearer $NewAccessToken" }
        try {
            Set-AzKeyVaultSecret -VaultName $env:KEY_VAULT_NAME -SecretName 'Beatport-AccessToken' -SecretValue $(ConvertTo-SecureString -String $NewAccessToken -AsPlainText -Force)
            Set-AzKeyVaultSecret -VaultName $env:KEY_VAULT_NAME -SecretName 'Beatport-RefreshToken' -SecretValue $(ConvertTo-SecureString -String $NewRefreshToken -AsPlainText -Force)
        } catch {
            Write-Error "Error updating Beatport Key Vault Secrets in Azure Key Vault [$($env:KEY_VAULT_NAME)]: $_"
        }
    } else {
        Write-Error 'No OAuth2 Access token was granted. Please ensure that the application Client ID and the user OAuth2 Refresh Token are valid.'
    }
    return $ApiHeaders
}