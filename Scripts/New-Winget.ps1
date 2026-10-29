[CmdletBinding()]
param( [string]$Destination, [switch]$Install )

# ------------------------------------------------------------------------------
# Product information
$productName = 'Winget'
$vendorName = 'Microsoft'
$productUrl = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
$searchPattern = 'Microsoft\.DesktopAppInstaller.*\.msixbundle$'
$dependencyPattern = 'Dependencies\.zip$'
$dependencyDir = 'Dependencies'
$dependencyFilter = '*x64*'
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

# get direct download Url of the package and validate
$downloadUrl = $response.assets |
    Where-Object { $_.name -match $searchPattern } |
    Select-Object -First 1 -ExpandProperty browser_download_url
if ([string]::IsNullOrEmpty($downloadUrl)) {
    Write-Host " * Download link was not detected" @fail
    exit 1
} else { Write-Host " * Found download link $downloadUrl" }

# get direct download Url of the dependencies and validate
$dependencyUrl = $response.assets |
    Where-Object { $_.name -match $dependencyPattern } |
    Select-Object -First 1 -ExpandProperty browser_download_url
if ([string]::IsNullOrEmpty($dependencyUrl)) {
    Write-Host " * Dependencies link was not detected" @fail
    exit 1
} else { Write-Host " * Found dependencies link $dependencyUrl" }
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Define variables to build path like Root\Vendor\AppName-Version
$fileName = Split-Path -Path $downloadUrl -Leaf
$dependencyFileName = Split-Path -Path $dependencyUrl -Leaf
$vendorDir = Join-Path -Path $rootPath -ChildPath $vendorName
$installerDir = Join-Path -Path $vendorDir -ChildPath "$productName-$version"
$installerPath = Join-Path -Path $installerDir -ChildPath $fileName
$dependencyArchive = Join-Path -Path $installerDir -ChildPath $dependencyFileName
$dependencyPath = Join-Path -Path $installerDir -ChildPath $dependencyDir

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
# Download package and dependencies. Reuse $requestParams with additional data
foreach ($download in @(
    @{ Url = $downloadUrl; Name = $fileName; Path = $installerPath },
    @{ Url = $dependencyUrl; Name = $dependencyFileName; Path = $dependencyArchive }
)) {
    $requestParams.Uri = $download.Url
    $requestParams.OutFile = $download.Path
    try {
        Write-Host " * Download '$($download.Name)' to '$installerDir'"
        $null = Invoke-WebRequest @requestParams
    } catch {
        Write-Host " * $($_.Exception.Message)" @fail
        exit 1
    }
}
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Extract dependencies from zip archive
try {
    Write-Host " * Expand '$dependencyFileName' to '$dependencyPath'"
    Expand-Archive -Path $dependencyArchive -DestinationPath $dependencyPath
    Remove-Item $dependencyArchive -Force
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

$appName = '<APPNAME>'
$appVersion = '<VERSION>'
$packageFile = '<FILE>'              # .msix / .msixbundle / .appx / .appxbundle
$dependencyDir = '<DEPDIR>'          # subfolder next to this script, '' if none
$dependencyFilter = '<DEPFILTER>'    # e.g. '*x64*', '' if none

$ErrorActionPreference = 'Stop'

# Name, version and architecture from the manifest inside a package.
# Used only to compare with what is already on the system.
function Get-PackageIdentity {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('AppxMetadata/AppxBundleManifest.xml')
        if (-not $entry) { $entry = $zip.GetEntry('AppxManifest.xml') }
        if (-not $entry) { throw "No package manifest found in $Path" }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $xml = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
    $id = $xml.DocumentElement.Identity
    [pscustomobject]@{
        Name         = $id.Name
        Version      = [version]$id.Version
        Architecture = if ($id.ProcessorArchitecture) { "$($id.ProcessorArchitecture)" } else { 'neutral' }
    }
}

# Highest version already on the system (any user or provisioned), $null if none
function Get-PresentVersion {
    param([string]$Name, [string]$Architecture)
    @(Get-AppxPackage -AllUsers -Name $Name) +
    @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $Name }) |
        Where-Object { $Architecture -eq 'neutral' -or "$($_.Architecture)" -eq $Architecture } |
        ForEach-Object { [version]$_.Version } |
        Sort-Object -Descending | Select-Object -First 1
}

try {
    Write-Host " * Install $appName $appVersion..." -NoNewLine

    $packagePath = Join-Path $PSScriptRoot $packageFile
    if (-not (Test-Path $packagePath)) { throw "Package not found: $packagePath" }
    $package = Get-PackageIdentity $packagePath

    $have = Get-PresentVersion $package.Name 'neutral'
    if ($have -and $have -ge $package.Version) {
        Write-Host "[OK] version $have is already present" -ForegroundColor 'Green'
        exit 0
    }

    $installParams = @{ PackagePath = $packagePath; Online = $true; SkipLicense = $true }

    # Skip dependencies already present in the same or a newer version,
    # otherwise provisioning fails with 0x80073D06
    if ($dependencyDir) {
        $dependencyPath = Join-Path $PSScriptRoot $dependencyDir
        if (-not (Test-Path $dependencyPath)) { throw "Dependency folder not found: $dependencyPath" }
        $dependencies = @()
        foreach ($file in Get-ChildItem $dependencyPath -Filter $dependencyFilter -File -Recurse) {
            $dep = Get-PackageIdentity $file.FullName
            $depHave = Get-PresentVersion $dep.Name $dep.Architecture
            if (-not $depHave -or $depHave -lt $dep.Version) { $dependencies += $file.FullName }
        }
        if ($dependencies) { $installParams.DependencyPackagePath = $dependencies }
    }

    $null = Add-AppxProvisionedPackage @installParams

    $have = Get-PresentVersion $package.Name 'neutral'
    if (-not $have -or $have -lt $package.Version) {
        throw "$($package.Name) $($package.Version) not found after provisioning"
    }
} catch {
    Write-Host "[FAIL]" -ForegroundColor 'Red'
    Write-Host $($_.Exception.Message) -ForegroundColor Red
    exit 1
}

Write-Host "[OK]" -ForegroundColor 'Green'
exit 0
'@

$installTemplate = $installTemplate.Replace('<FILE>', $fileName)
$installTemplate = $installTemplate.Replace('<APPNAME>', $productName)
$installTemplate = $installTemplate.Replace('<VERSION>', $version)
$installTemplate = $installTemplate.Replace('<DEPDIR>', $dependencyDir)
$installTemplate = $installTemplate.Replace('<DEPFILTER>', $dependencyFilter)
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
