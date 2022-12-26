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

# Authenticate with Azure PowerShell using MSI.
if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity
}

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