[CmdletBinding()]
param( [string]$Destination, [switch]$Install )

# ------------------------------------------------------------------------------
# Product information
$productName = 'WinSCP'
$vendorName = 'WinSCP'
$productUrl = 'https://sourceforge.net/projects/winscp/rss?path=/WinSCP'
$searchPattern = 'WinSCP-(\d+(\.\d+)+)-Setup\.exe/download$'
$installParams = '/ALLUSERS /VERYSILENT /NORESTART /SUPPRESSMSGBOXES'
$exitCodes = "0, 3010"
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# basic configuration
$rootPath = if ([string]::IsNullOrEmpty($Destination)) { $PSScriptRoot }
else { $Destination }
$fail = @{'ForegroundColor' = 'Red'}
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# get data from source
Write-Host "Build installation for $vendorName $productName :" -ForegroundColor Yellow
$ProgressPreference = 'SilentlyContinue'
$requestParams = @{
    'Uri'=$productUrl
    'UseBasicParsing'=$true
    'DisableKeepAlive'=$true
    'UserAgent'='Wget'
    'ErrorAction'='Stop'
}
try {
    $response = Invoke-RestMethod @requestParams
} catch {
    Write-Host " * $($_.Exception.Message)" @fail
    exit 1
}
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# get product version and validate
$item = $response | Where-Object { $_.link -match $searchPattern } | Select-Object -First 1
$version = [regex]::Match("$($item.link)", $searchPattern).Groups[1].Value
if ($version -match "\d+(\.\d+)+") {
    Write-Host " * Found product version $version"
} else {
    Write-Host " * Cannot detect product version." @fail
    exit 1
}

# get direct download Url and validate
$downloadUrl = $item.link
if ([string]::IsNullOrEmpty($downloadUrl)) {
    Write-Host " * Download link was not detected" @fail
    exit 1
} else { Write-Host " * Found download link $downloadUrl" }
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Define variables to build path like Root\Vendor\AppName-Version
$fileName = ($downloadUrl -split '/')[-2]
$vendorDir = Join-Path -Path $rootPath -ChildPath $vendorName
$installerDir = Join-Path -Path $vendorDir -ChildPath "$productName-$version"
$installerPath = Join-Path -Path $installerDir -ChildPath $fileName

# Create folder Structure
try {
    Write-Host " * Create folder '$installerDir'"
    $null = New-Item -Path $installerDir -ItemType Directory -Force
} catch {
    Write-Host " * $($_.Exception.Message)" @fail
    exit 1
}
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Download installer
$requestParams.Uri = $downloadUrl
$requestParams.OutFile = $installerPath
try {
    Write-Host " * Download '$fileName' to '$installerDir'"
    $null = Invoke-WebRequest @requestParams
} catch {
    Write-Host " * $($_.Exception.Message)" @fail
    exit 1
}
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Create install script from tempalte
$InstallTemplate = @'
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

$InstallTemplate = $InstallTemplate.Replace('<EXE>', '$PSScriptRoot\<FILE>')
$InstallTemplate = $InstallTemplate.Replace('<PARAMS>', $installParams)
$InstallTemplate = $InstallTemplate.Replace('<FILE>', $fileName)
$InstallTemplate = $InstallTemplate.Replace('<ExitCodes>', $exitCodes)
$InstallTemplate = $InstallTemplate.Replace('<APPNAME>', $productName)
$InstallTemplate = $InstallTemplate.Replace('<VERSION>', $version)
$scriptPath = Join-Path -Path $installerDir -ChildPath "Install.ps1"
try {
    Write-Host " * Create 'install.ps1' in '$installerDir'"
    $InstallTemplate | Out-File -FilePath $scriptPath -Encoding utf8
    Write-Host "Done`n" -ForegroundColor Green
} catch {
    Write-Host " * $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# install product
if ( $Install ) { & $scriptPath }
# ------------------------------------------------------------------------------