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
