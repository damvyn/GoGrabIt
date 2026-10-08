[CmdletBinding()]
param( [string]$Destination, [switch]$Install )

# Check destination
$rootPath = if ([string]::IsNullOrEmpty($Destination)) { $PSScriptRoot }
else { $Destination }

# Product information
$productName = 'Notepad++'
$vendorName = 'Notepad++ team'
$productUrl = 'https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest'
$searchPattern = '*Installer.x64.msi'
$installParams = '/i `"$PSScriptRoot\<FILE>`" ALLUSERS=1 REBOOT=ReallySuppress /qb'
$exitCodes = "0, 3010"

$fail = @{'ForegroundColor' = 'Red'}

# Request data from GitHub to get version and direct download link
Write-Host "Build installation for $vendorName $productName :" -ForegroundColor Yellow
$ProgressPreference = 'SilentlyContinue' # disable progress bar and speed-up download process
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

# get productVersion
$version = $response.tag_name -replace '[A-Za-z]', ''
if ($version -match "\d+(\.\d+)+") {
    Write-Host " * Found product version $version"
} else {
    Write-Host " * Cannot detect product version." @fail
    exit 1
}

# get downloadUrl
$downloadUrl = $response.assets |
    Where-Object { $_.name -like $searchPattern } |
    Select-Object -First 1 -ExpandProperty browser_download_url
if ([string]::IsNullOrEmpty($downloadUrl)) {
    Write-Host " * Download link was not detected" @fail
    exit 1
} else { Write-Host " * Found download link $downloadUrl" }

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


# Create install script
$scriptTemplate = @'
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

$scriptTemplate = $scriptTemplate.Replace('<EXE>', 'msiexec')
$scriptTemplate = $scriptTemplate.Replace('<PARAMS>', $installParams)
$scriptTemplate = $scriptTemplate.Replace('<FILE>', $fileName)
$scriptTemplate = $scriptTemplate.Replace('<ExitCodes>', $exitCodes)
$scriptTemplate = $scriptTemplate.Replace('<APPNAME>', $productName)
$scriptTemplate = $scriptTemplate.Replace('<VERSION>', $version)
$scriptPath = Join-Path -Path $installerDir -ChildPath "Install.ps1"
try {
    Write-Host " * Create 'install.ps1' in '$installerDir'"
    $scriptTemplate | Out-File -FilePath $ScriptPath -Encoding utf8
} catch {
    Write-Host " * $($_.Exception.Message)" @fail
    exit 1
}

# ------------------------------------------------------------------------------
# install product
if ( $Install ) { & $scriptPath }
Write-Host "Done`n" -ForegroundColor Green
# ------------------------------------------------------------------------------