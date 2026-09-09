[CmdletBinding()]
param(
    [string]$Destination
)

# Check destination
$RootPath = if ($Destination) { $Destination } else { $PsScriptRoot }

# Product information
$ProductName = 'PaintDotNet'
$VendorName = 'dotPND'
$ProductUrl = 'https://api.github.com/repos/paintdotnet/release/releases/latest'
$SearchPattern = '*winmsi*x64'
$InstallParams = '/i `"$PSScriptRoot\<FILE>`" ALLUSERS=1 REBOOT=ReallySuppress /qb'
$ExitCodes = "0, 3010"

# Request data from GitHub to get version and direct download link
Write-Host "Build installation for $VendorName $ProductName :" -ForegroundColor Yellow
$ProgressPreference = 'SilentlyContinue' # disable progress bar and speed-up download process
$Params = @{
    'Uri'=$ProductUrl
    'UseBasicParsing'=$true
    'DisableKeepAlive'=$true
    'ErrorAction'='Stop'
}
try {
    $GitHubReply = Invoke-RestMethod @Params
} catch {
    Write-Host " * $($_.Exception.Message)" -ForegroundColor Red
    return 1
}

$Version = $GitHubReply.tag_name -replace '[A-Za-z]', ''
$DownloadUrl = ($GitHubReply.assets | 
                Where-Object{$_.Name -like "$SearchPattern*zip"}
               ).browser_download_url
Write-Host " * Found version $Version"

# Define variables to build path like Root\Vendor\AppName-Version
$FileName = Split-Path -Path $DownloadUrl -Leaf
$VendorDir = Join-Path -Path $RootPath -ChildPath $VendorName
$InstallerDir = Join-Path -Path $VendorDir -ChildPath "$ProductName-$Version"
$InstallerPath = Join-Path -Path $InstallerDir -ChildPath $FileName

# Create folder Structure
try {
    Write-Host " * Create folder '$InstallerDir'"
    $null = New-Item -Path $InstallerDir -ItemType Directory -Force
} catch {
    Write-Host " * $($_.Exception.Message)" -ForegroundColor Red
    return 1
}


# Download installer. Reuse $Params with additional data
$Params.Uri = $DownloadUrl
$Params.OutFile = $InstallerPath
try {
    Write-Host " * Download '$FileName' to '$InstallerDir'"
    $null = Invoke-WebRequest @Params
} catch {
    Write-Host " * $($_.Exception.Message)" -ForegroundColor Red
    return 1
}


# Extract installer from zip archive
try {
    Expand-Archive -Path $InstallerPath -DestinationPath $InstallerDir
} catch {
    Write-Host " * $($_.Exception.Message)" -ForegroundColor Red
    return 1
}

try {
    Remove-Item $InstallerPath
}  catch {
    Write-Host " * $($_.Exception.Message)" -ForegroundColor Red
    return 1
}

$InstallerPath = (Get-ChildItem -Path $InstallerDir -Filter "$SearchPattern*msi"|
    Select-Object -First 1).FullName

# Create install script
$Template = @'
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$execute = "<EXE>"
$withParams = "<PARAMS>"
$exitCodes = <ExitCodes>

try { 
    $exitCode = ( Start-Process -FilePath $execute -ArgumentList $withParams -Wait -PassThru ).ExitCode 
} catch {  Write-Host $($_.Exception.Message) -ForegroundColor Red }

if ($exitCode -notin $ExitCodes) { 
     Write-Host "Unexpected exit code: $exitCode" -ForegroundColor Red }

return $exitCode
'@

$Template = $Template.Replace('<EXE>', 'msiexec')
$Template = $Template.Replace('<PARAMS>', $InstallParams)
$Template = $Template.Replace('<FILE>', $FileName)
$Template = $Template.Replace('<ExitCodes>', $ExitCodes)
$ScriptPath = Join-Path -Path $InstallerDir -ChildPath "Install.ps1"
try {
    Write-Host " * Create 'install.ps1' in '$InstallerDir'"
    $Template | Out-File -FilePath $ScriptPath -Encoding utf8
    Write-Host "Done`n" -ForegroundColor Green
} catch {
    Write-Host " * $($_.Exception.Message)" -ForegroundColor Red
    return 1
}
