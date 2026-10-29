[CmdletBinding()]
param( [string]$Destination, [switch]$Install )

# ------------------------------------------------------------------------------
# Product information
$productName = 'OneDrive'
$vendorName = 'Microsoft'
$productUrl = 'https://g.live.com/1rewlive5skydrive/OneDriveProductionV2'
$installParams = '/allusers /silent'
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
try {
    $xml = [xml]$response.Content.TrimStart([char]0xFEFF)
} catch {
    Write-Host " * Cannot parse response: $($_.Exception.Message)" @fail
    exit 1
}
# throttle 100 is the deferred ring, 50 is the production ring
$release = @($xml.root.update) | Where-Object { $_.throttle -eq '100' } | Select-Object -First 1
$version = $release.currentVersion
$downloadUrl = $release.amd64binary.url

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
$timeoutSeconds = 600
$installParams = @{
    'FilePath' = "<EXE>"
    'ArgumentList' = "<PARAMS>"
    'PassThru' = $true
}

# Do not use Start-Process -Wait: it also waits for every process and service
# started by the installer, and they never exit.
try {
    Write-Host " * Install <APPNAME> <VERSION>..." -NoNewLine
    $process = Start-Process @installParams
    # cache the handle, otherwise ExitCode can be empty for a fast process
    $null = $process.Handle
    $exited = $process.WaitForExit($timeoutSeconds * 1000)
} catch {
    Write-Host "[FAIL]" -ForegroundColor 'Red'
    Write-Host $($_.Exception.Message) -ForegroundColor Red
    exit 1
}

if ($exited) {
    $exitCode = $process.ExitCode
    if ($exitCode -notin $exitCodes) {
        Write-Host "[FAIL] Error Code: $exitCode" -ForegroundColor Red
    } else {
        Write-Host "[OK]" -ForegroundColor 'Green'
    }
    exit $exitCode
}

# Installer is still running after the timeout. Kill it and report failure
Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
Write-Host "[FAIL] Installation was not completed in $timeoutSeconds seconds" -ForegroundColor Red
exit 1
'@

$installTemplate = $installTemplate.Replace('<EXE>', '$PSScriptRoot\<FILE>')
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
