[CmdletBinding()]
param( [string]$Destination, [switch]$Install )

# ------------------------------------------------------------------------------
# Product information
$productName = 'uv'
$vendorName = 'Astral'
$productUrl = 'https://api.github.com/repos/astral-sh/uv/releases/latest'
$searchPattern = '^uv-x86_64-pc-windows-msvc\.zip$'
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
# Create install script from tempalte
$installTemplate = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$expandParams = @{
    'Path' = "$PSScriptRoot\<FILE>"
    'DestinationPath' = 'C:\Program Files\astral.sh\uv'
    'Force' = $true
}

try {
    Expand-Archive @expandParams
} catch {
    Write-Host $($_.Exception.Message) -ForegroundColor Red
    exit 1
}

$exitCode = 0
foreach ($file in @('uv.exe', 'uvx.exe', 'uvw.exe') ) {
    $niParams = @{
        'ItemType' = 'HardLink'
        'Path' = "C:\Windows\System32\${file}"
        'Target' = "C:\Program Files\astral.sh\uv\${file}"
        'Force' = $true
    }
    try {
        $null = New-Item @niParams
        Write-Host "Hardlink for ${file} was created"
    } catch {
        Write-Host "Failed to create hardlink for ${file}: $($_.Exception.Message)" -ForegroundColor Red
        $exitCode = 1
    }
}
exit $exitCode
'@

$installTemplate = $installTemplate.Replace('<FILE>', $fileName)
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