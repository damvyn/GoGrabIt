[CmdletBinding()]
param( [string]$Destination, [switch]$Install )

# ------------------------------------------------------------------------------
# Product information
$productName = 'LibreOffice'
$vendorName = 'LibreOffice'
$productUrl = 'https://download.documentfoundation.org/libreoffice/stable/'
$installParams = '/i `"$PSScriptRoot\<FILE>`" ADDLOCAL=ALL ALLUSERS=1 REBOOT=ReallySuppress /qn'
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
    $response = Invoke-WebRequest @requestParams
} catch {
    Write-Host " * $($_.Exception.Message)" @fail
    exit 1
}
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# get product version and direct download Url
$version = $response.Links |
    Where-Object { $_.href -match '^(\d+(\.\d+)+)/?$' } |
    ForEach-Object { $_.href.TrimEnd('/') } |
    Sort-Object -Property { $_ -as [version] } |
    Select-Object -Last 1

# the installer is listed in the folder of the latest version
if ($version) {
    $sourceLocation = "$productUrl$version/win/x86_64/"
    $requestParams.Uri = $sourceLocation
    try {
        $response = Invoke-WebRequest @requestParams
    } catch {
        Write-Host " * $($_.Exception.Message)" @fail
        exit 1
    }
    $fileName = $response.Links |
        Where-Object { $_.href -match '^LibreOffice_(\d+(\.\d+)+)_Win_x86-64\.msi$' } |
        Select-Object -First 1 -ExpandProperty href
    $downloadUrl = if ($fileName) { $sourceLocation + $fileName }
}

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
