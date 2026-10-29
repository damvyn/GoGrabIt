[CmdletBinding()]
param(
    [string]$Destination,
    [switch]$Install,
    [Parameter(HelpMessage = 'Release channels to build. 8.0 and 10.0 are LTS, 9.0 is STS. All channels by default')]
    [ValidateSet('8.0', '9.0', '10.0')]
    [string[]]$Channel = @('8.0', '9.0', '10.0')
)

# ------------------------------------------------------------------------------
# Product information
$productName = 'Windows Desktop Runtime'
$vendorName = 'Microsoft'
$productUrl = 'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/<CHANNEL>/releases.json'
$searchPattern = '-win-x64\.exe$'
$installParams = '/install /quiet /norestart'
$exitCodes = "0, 3010"
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# basic configuration
$rootPath = if ([string]::IsNullOrEmpty($Destination)) { $PSScriptRoot }
else { $Destination }
$fail = @{'ForegroundColor' = 'Red'}
$ProgressPreference = 'SilentlyContinue'
$failed = $false
$installScripts = @()
# ------------------------------------------------------------------------------

$installTemplateText = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$exitCodes = <ExitCodes>
$installParams = @{
    'FilePath' = "<EXE>"
    'ArgumentList' = "<PARAMS>"
    'Wait' = $true
    'PassThru' = $true
}

try {
    Write-Host " * Install <APPNAME> <VERSION>..." -NoNewLine
    $exitCode = ( Start-Process @installParams).ExitCode
} catch {
    Write-Host "[FAIL]" -ForegroundColor 'Red'
    Write-Host $($_.Exception.Message) -ForegroundColor Red
    exit 1
}

if ($exitCode -notin $exitCodes) {
    Write-Host "[FAIL] Error Code: $exitCode" -ForegroundColor Red
} else {
    Write-Host "[OK]" -ForegroundColor 'Green'
}
exit $exitCode
'@

Write-Host "Build installation for $vendorName $productName :" -ForegroundColor Yellow

foreach ($releaseChannel in $Channel) {
    Write-Host "Channel ${releaseChannel}:" -ForegroundColor Yellow

    # --------------------------------------------------------------------------
    # get data from source
    $requestParams = @{
        'Uri'=$productUrl.Replace('<CHANNEL>', $releaseChannel)
        'UseBasicParsing'=$true
        'DisableKeepAlive'=$true
        'ErrorAction'='Stop'
    }
    try {
        $response = Invoke-RestMethod @requestParams
    } catch {
        Write-Host " * $($_.Exception.Message)" @fail
        $failed = $true
        continue
    }

    # get product version and validate
    $version = $response.'latest-release'
    if ($version -match "\d+(\.\d+)+") {
        Write-Host " * Found product version $version"
    } else {
        Write-Host " * Cannot detect product version." @fail
        $failed = $true
        continue
    }

    # get direct download Url and validate
    $downloadUrl = $response.releases |
        Where-Object { $_.'release-version' -eq $version } |
        ForEach-Object { $_.windowsdesktop.files.url } |
        Where-Object { $_ -match $searchPattern } |
        Select-Object -First 1
    if ([string]::IsNullOrEmpty($downloadUrl)) {
        Write-Host " * Download link was not detected" @fail
        $failed = $true
        continue
    } else { Write-Host " * Found download link $downloadUrl" }
    # --------------------------------------------------------------------------

    # --------------------------------------------------------------------------
    # Define variables to build path like Root\Vendor\AppName-Version
    $fileName = [uri]::UnescapeDataString((Split-Path -Path $downloadUrl -Leaf))
    $vendorDir = Join-Path -Path $rootPath -ChildPath $vendorName
    $installerDir = Join-Path -Path $vendorDir -ChildPath "$productName-$version"
    $installerPath = Join-Path -Path $installerDir -ChildPath $fileName

    # Create folder Structure
    try {
        Write-Host " * Create folder '$installerDir'"
        $null = New-Item -Path $installerDir -ItemType Directory -Force
    } catch {
        Write-Host " * $($_.Exception.Message)" @fail
        $failed = $true
        continue
    }
    # --------------------------------------------------------------------------

    # --------------------------------------------------------------------------
    # Download installer. Reuse $requestParams with additional data
    $requestParams.Uri = $downloadUrl
    $requestParams.OutFile = $installerPath
    try {
        Write-Host " * Download '$fileName' to '$installerDir'"
        $null = Invoke-WebRequest @requestParams
    } catch {
        Write-Host " * $($_.Exception.Message)" @fail
        $failed = $true
        continue
    }
    # --------------------------------------------------------------------------

    # --------------------------------------------------------------------------
    # Create install script from tempalte
    $installTemplate = $installTemplateText.Replace('<EXE>', '$PSScriptRoot\<FILE>')
    $installTemplate = $installTemplate.Replace('<PARAMS>', $installParams)
    $installTemplate = $installTemplate.Replace('<FILE>', $fileName)
    $installTemplate = $installTemplate.Replace('<ExitCodes>', $exitCodes)
    $installTemplate = $installTemplate.Replace('<APPNAME>', $productName)
    $installTemplate = $installTemplate.Replace('<VERSION>', $version)
    $scriptPath = Join-Path -Path $installerDir -ChildPath "Install.ps1"
    try {
        Write-Host " * Create 'install.ps1' in '$installerDir'"
        $installTemplate | Out-File -FilePath $scriptPath -Encoding utf8
    } catch {
        Write-Host " * $($_.Exception.Message)" @fail
        $failed = $true
        continue
    }
    $installScripts += $scriptPath
    # --------------------------------------------------------------------------
}

if ($failed) {
    Write-Host "Some channels were not built" @fail
    exit 1
}

# ------------------------------------------------------------------------------
# install product
if ( $Install ) { foreach ($scriptPath in $installScripts) { & $scriptPath } }
Write-Host "Done`n" -ForegroundColor Green
# ------------------------------------------------------------------------------
