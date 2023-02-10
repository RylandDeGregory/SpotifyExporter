<#
    .SYNOPSIS
        Obtain Refresh Token from Beatport API using the OAuth 2 client authorization code flow
    .DESCRIPTION
        This function helps a user complete the flow interactively by pasting the redirected URL into the PowerShell session
        A Beatport Refresh Token is obtained using the Client Authorization Code
    .NOTES
        https://api.beatport.com/v4/docs/
#>
[CmdletBinding()]
param (
    # Beatport Developer Application Client ID
    [Parameter()]
    [string] $ClientId = '0GIvkCltVIuPkkwSJHp6NDb3s0potTjLBQr388Dd',

    # Beatport Developer Application Redirect URI
    [Parameter()]
    [Alias('RedirectUrl')]
    [string] $RedirectUri = 'https://api.beatport.com/v4/auth/o/post-message/'
)
#region Init
$ErrorActionPreference = 'Stop'

[System.Uri]$RedirectUri = $RedirectUri
$AuthCodeUri = "https://api.beatport.com/v4/auth/o/authorize/?client_id=$ClientId&response_type=code&redirect_uri=$RedirectUri"
$TokenUri    = 'https://api.beatport.com/v4/auth/o/token/'
#endregion Init

#region OpenBrowser
Write-Output "[INFO] Navigate to the following URL in a web browser:`n$AuthCodeUri"
#endregion OpenBrowser

#region GetAuthCode
$AuthResponseUri = Read-Host 'Paste the entire URL you are redirected to'
$AuthResponseUri = [System.Uri]$AuthResponseUri
#endregion GetAuthCode

#region ValidateAuthCode
$AuthResponseQueryString = [System.Web.HttpUtility]::ParseQueryString($AuthResponseUri.Query)

if ([string]::IsNullOrEmpty($AuthResponseUri.OriginalString)) {
    Write-Error '[ERROR] Response cannot be empty'
}
if ($AuthResponseQueryString['code']) {
    Write-Verbose 'Received Authorization Code for user'
    $AuthCode = $AuthResponseQueryString['code']
} else {
    Write-Error '[ERROR] Response does not contain an Authorization Code'
}
#endregion ValidateAuthCode

#region GetRefreshToken
$TokenBody = @{
    grant_type    = 'authorization_code'
    code          = $AuthCode
    redirect_uri  = $RedirectUri
    client_id     = $ClientId
}

try {
    Write-Verbose 'Request Beatport API Refresh Token using Authorization Code'
    $TokenResponse = Invoke-WebRequest -Method Post $TokenUri -Body $TokenBody -ContentType 'application/x-www-form-urlencoded'
} catch {
    Write-Error "[ERROR] Error obtaining Refresh Token from Beatport API: $_"
}

Write-Output '*****Beatport Refresh Token*****'
Write-Output $TokenResponse.Content | ConvertFrom-Json
Write-Output '*******************************'
#endregion GetRefreshToken