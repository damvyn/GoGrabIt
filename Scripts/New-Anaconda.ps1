[CmdletBinding()]
param( [string]$Destination, [switch]$Install )

# Check destination
$rootPath = if ([string]::IsNullOrEmpty($Destination)) { $PSScriptRoot }
else { $Destination }

# Product information
# ==============================================================================
$productName = 'Anaconda3'
$vendorName = 'Anaconda'
$productUrl = 'https://repo.anaconda.com/archive'
$searchPattern = 'Anaconda3-.*-Windows-x86_64.exe'
$installParams = '/InstallationType=AllUsers /RegisterPython=1 /S /D=C:\ProgramData\Anaconda3'
$exitCodes = "0, 3010"
# ==============================================================================

Write-Host "Build installation for $vendorName $productName :" -ForegroundColor Yellow
$fail = @{'ForegroundColor' = 'Red'}

# Request data from repo.anaconda.com to get version and direct download link
$ProgressPreference = 'SilentlyContinue' # disable progress bar and speed-up download process
$requestParams = @{
    'Uri'= $productUrl, ".files.json" -join "/"
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

# get filename
$fileName = $response.PsObject.Properties |
    Where-Object { $_.Name -match "$searchPattern" } |
    Sort-Object -Property {[double][long]$_.Value.mtime} |
    Select-Object -Last 1 -ExpandProperty 'Name'
if ( [string]::IsNullOrEmpty($fileName) ) {
    Write-Host " * Cannot find expected filename" @fail
    exit 1
} else {
    Write-Host " * Found $fileName"
}

# ger version
$version = $fileName.Replace('Anaconda3-', '').replace('-Windows-x86_64.exe', '')
if ($version -match "\d+(\.\d+)+(-\d+)?") {
    Write-Host " * Found product version $version"
} else {
    Write-Host " * Cannot detect product version." @fail
    exit 1
}

# get downloadUrl
$downloadUrl = $productUrl, $fileName -join '/'
Write-Host " * Download link must be $downloadUrl"

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
Write-Host " * Download '$fileName' to '$installerDir'"
try {
    $null = Invoke-WebRequest @requestParams
} catch {
    Write-Host " * $($_.Exception.Message)" @fail
    exit 1
}


# Install script template
# ==============================================================================
$scriptTemplate = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$exitCodes = <ExitCodes>
$installParams = @{
    'FilePath' = "$PSScriptRoot\<EXE>"
    'ArgumentList' = "<PARAMS>"
    'Wait' = $true
    'PassThru' = $true
}

try {
    Write-Host " * Install <APPNAME> <VERSION>..."
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
# ==============================================================================
# Create install script
$scriptTemplate = $scriptTemplate.Replace('<EXE>', $fileName)
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