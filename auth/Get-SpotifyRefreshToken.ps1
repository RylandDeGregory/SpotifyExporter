<#
    .SYNOPSIS
        Obtain Refresh Token from Spotify API using the OAuth 2 client authorization code flow
    .DESCRIPTION
        This function utilizes a .NET HTTP Listener to parse the Redirect URL containing the Authorization Code
        Alternatively, a user can choose to complete the flow interactively by pasting the Redirect URL into the PowerShell session
        A Spotify Refresh Token is obtained using the Client Authorization Code and the Spotify Developer Application credentials
    .NOTES
        https://developer.spotify.com/dashboard
        https://developer.spotify.com/documentation/general/guides/authorization-guide/#authorization-code-flow
#>
[CmdletBinding()]
param (
    # Spotify Developer Application Client ID
    [Parameter(Mandatory)]
    [string] $ClientId,

    # Spotify Developer Application Client Secret
    [Parameter(Mandatory)]
    [string] $ClientSecret,

    # Spotify Developer Application Redirect URI
    [Parameter(Mandatory)]
    [Alias('RedirectUrl')]
    [string] $RedirectUri,

    # Disable automatic browser opening
    [Parameter()]
    [switch] $ManualAuth
)
#region Init
$ErrorActionPreference = 'Stop'

[System.Uri]$RedirectUri = $RedirectUri
$EncodedRedirectUri = [System.Web.HTTPUtility]::UrlEncode($RedirectUri.AbsoluteUri)
# Request only read scopes
$ApiScopes = @(
    'playlist-read-private',
    'playlist-read-collaborative',
    'user-top-read',
    'user-follow-read',
    'user-library-read',
    'user-read-private',
    'user-read-email'
) -join '%20'
$AuthState   = (New-Guid).ToString()
$AuthCodeUri = "https://accounts.spotify.com/authorize?client_id=$ClientId&response_type=code&redirect_uri=$EncodedRedirectUri&state=$AuthState&scope=$ApiScopes"
$TokenUri    = 'https://accounts.spotify.com/api/token'
#endregion Init

#region StartListener
if ($ManualAuth) {
    $HttpListenerReady = $false
} else {
    $RedirectPrefix = "$($RedirectUri.Scheme)://$($RedirectUri.Authority)/"
    $HttpListener = New-Object System.Net.HttpListener
    $HttpListener.Prefixes.Add($RedirectPrefix)
    $HttpListener.Start()
    if ($HttpListener.IsListening) {
        Write-Verbose 'HTTP Listener is ready'
        $HttpListenerReady = $true
    } else {
        Write-Verbose 'HTTP Listener is not ready. Using ManualAuth method'
        $HttpListenerReady = $false
    }
}
#endregion StartListener

#region OpenBrowser
if ($ManualAuth) {
    Write-Output "[INFO] Navigate to the following URL in a web browser:`n$AuthCodeUri"
} else {
    if ($IsMacOS) {
        Write-Output '[INFO] Opening MacOS default browser for user login'
        Invoke-Expression 'open -u "$AuthCodeUri"'
    } elseif ($IsLinux) {
        Write-Output '[INFO] Opening Linux default browser for user login (requires a freedesktop.org compliant desktop)'
        Start-Process xdg-open $AuthCodeUri
    } else {
        Write-Output '[INFO] Opening Windows default browser for user login'
        Invoke-Expression "rundll32 url.dll, FileProtocolHandler $AuthCodeUri"
    }
}
#endregion OpenBrowser

#region GetAuthCode
if ($HttpListenerReady) {
    Write-Output '[INFO] Please complete browser login within 60 seconds'
    $Context = $null
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        while ($HttpListener.IsListening -and $Stopwatch.Elapsed -lt [TimeSpan]::ParseExact('01', 'mm', $null)) {

            if ($null -eq $Context) {
                $Context = $HttpListener.GetContextAsync()
            }
            if ($Context.IsCompleted) {
                $Result          = $Context.Result
                $Context         = $null
                $AuthResponseUri = $Result.Request.Url

                $ContextResponse = $Result.Response
                $BrowserDialog = [System.Text.Encoding]::UTF8.GetBytes('Login complete. You may now close this window.')
                $ContextResponse.ContentLength64 = $BrowserDialog.Length
                $ContextResponse.OutputStream.Write($BrowserDialog, 0, $BrowserDialog.Length)
                $ContextResponse.OutputStream.Close()
                $Stopwatch.Stop()
                break
            }
        }
    } catch {
        Write-Error "[ERROR] Error encountered while listening for browser Response: $_"
    } finally {
        Write-Verbose 'Stop HTTP Listener'
        $HttpListener.Stop()
    }
} else {
    $AuthResponseUri = Read-Host 'Paste the entire URL you are redirected to'
    $AuthResponseUri = [System.Uri]$AuthResponseUri
}
#endregion GetAuthCode

#region ValidateAuthCode
$AuthResponseQueryString = [System.Web.HttpUtility]::ParseQueryString($AuthResponseUri.Query)

if ([string]::IsNullOrEmpty($AuthResponseUri.OriginalString)) {
    Write-Error '[ERROR] Response cannot be empty'
}
if ($AuthResponseQueryString['state'] -ne $AuthState) {
    Write-Error "[ERROR] Response state [$($AuthResponseQueryString['state'])] does not match the request state [$AuthState]"
}
if ($AuthResponseQueryString['error']) {
    Write-Error "[ERROR] Response contains an error: $($AuthResponseQueryString.Error)"
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
    client_secret = $ClientSecret
}

try {
    Write-Verbose 'Request Spotify API Refresh Token using Authorization Code and Application credentials'
    $TokenResponse = Invoke-RestMethod -Method Post -Uri $TokenUri -Body $TokenBody
} catch {
    Write-Error "[ERROR] Error obtaining Refresh Token from Spotify API: $_"
}

Write-Output '*****Spotify Refresh Token*****'
Write-Output $TokenResponse.refresh_token
Write-Output '*******************************'
#endregion GetRefreshToken