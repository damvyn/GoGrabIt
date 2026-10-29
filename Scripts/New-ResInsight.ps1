[CmdletBinding()]
param( [string]$Destination, [switch]$Install )

# ------------------------------------------------------------------------------
# Product information
$productName = 'ResInsight'
$vendorName = 'Ceetron'
$productUrl = 'https://api.github.com/repos/OPM/ResInsight/releases/latest'
$searchPattern = 'win64\.zip$'
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
# get product version and validate
$version = $response.tag_name -replace '[A-Za-z]', ''
if ($version -match "\d+(\.\d+)+") {
    Write-Host " * Found product version $version"
} else {
    Write-Host " * Cannot detect product version." @fail
    exit 1
}

# get direct download Url and validate
$downloadUrl = $response.assets |
    Where-Object { $_.name -match $searchPattern } |
    Select-Object -First 1 -ExpandProperty browser_download_url
if ([string]::IsNullOrEmpty($downloadUrl)) {
    Write-Host " * Download link was not detected" @fail
    exit 1
} else { Write-Host " * Found download link $downloadUrl" }
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Define variables to build path like Root\Vendor\AppName-Version
$fileName = Split-Path -Path $downloadUrl -Leaf
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
# Create install script. The product is a portable zip: install script only unpacks it
$InstallTemplate = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$archivePath = "$PSScriptRoot\<FILE>"
$targetDir = Join-Path -Path $env:ProgramFiles -ChildPath ([IO.Path]::GetFileNameWithoutExtension($archivePath))
$expandParams = @{
    'Path' = $archivePath
    'DestinationPath' = $env:ProgramFiles
    'Force' = $true
    'ErrorAction' = 'Stop'
}

Write-Host " * Install <APPNAME> <VERSION>..." -NoNewLine
if (-not (Test-Path -Path $archivePath -PathType Leaf)) {
    Write-Host "[FAIL]" -ForegroundColor 'Red'
    Write-Host "Archive '$archivePath' was not found" -ForegroundColor Red
    exit 1
}

try {
    Expand-Archive @expandParams
} catch {
    Write-Host "[FAIL]" -ForegroundColor 'Red'
    Write-Host $($_.Exception.Message) -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -Path $targetDir -PathType Container)) {
    Write-Host "[FAIL]" -ForegroundColor 'Red'
    Write-Host "Folder '$targetDir' was not created" -ForegroundColor Red
    exit 1
}
Write-Host "[OK]" -ForegroundColor 'Green'
exit 0
'@

$InstallTemplate = $InstallTemplate.Replace('<FILE>', $fileName)
$InstallTemplate = $InstallTemplate.Replace('<APPNAME>', $productName)
$InstallTemplate = $InstallTemplate.Replace('<VERSION>', $version)
$scriptPath = Join-Path -Path $installerDir -ChildPath "Install.ps1"
try {
    Write-Host " * Create 'install.ps1' in '$installerDir'"
    $InstallTemplate | Out-File -FilePath $scriptPath -Encoding utf8
} catch {
    Write-Host " * $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# install product
if ( $Install ) { & $scriptPath }
Write-Host "Done`n" -ForegroundColor Green
# ------------------------------------------------------------------------------