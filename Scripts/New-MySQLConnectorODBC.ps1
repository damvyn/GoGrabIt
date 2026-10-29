[CmdletBinding()]
param( [string]$Destination, [switch]$Install )

# ------------------------------------------------------------------------------
# Product information
$productName = 'MySQL Connector ODBC'
$vendorName = 'Oracle'
$productUrl = 'https://api.github.com/repos/mysql/mysql-connector-odbc/tags'
$installParams = '/i `"$PSScriptRoot\<FILE>`" REBOOT=ReallySuppress /qn'
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
# get product version and direct download Url
$version = $response |
    Where-Object { $_.name -match '^\d+(\.\d+)+$' } |
    Sort-Object -Property { [version]$_.name } |
    Select-Object -Last 1 -ExpandProperty name
$shortVersion = ($version -split '\.')[0..1] -join '.'
$fileName = "mysql-connector-odbc-$version-winx64.msi"
$downloadUrl = if ($version) { "https://cdn.mysql.com/Downloads/Connector-ODBC/$shortVersion/$fileName" }

# validate
if ($version -match "\d+(\.\d+)+") {
    Write-Host " * Found product version $version"
} else {
    Write-Host " * Cannot detect product version." @fail
    exit 1
}
if ([string]::IsNullOrEmpty($downloadUrl)) {
    Write-Host " * Download link was not detected" @fail
    exit 1
} else { Write-Host " * Found download link $downloadUrl" }
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Define variables to build path like Root\Vendor\AppName-Version
if ([string]::IsNullOrEmpty($fileName)) {
    $fileName = [uri]::UnescapeDataString((Split-Path -Path $downloadUrl -Leaf))
}
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
# Download installer. Reuse $requestParams with additional data
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
$installTemplate = @'
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

$installTemplate = $installTemplate.Replace('<EXE>', 'msiexec')
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
    exit 1
}
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# install product
if ( $Install ) { & $scriptPath }
Write-Host "Done`n" -ForegroundColor Green
# ------------------------------------------------------------------------------
