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
    $exitCode = ( Start-Process @installParams).ExitCode
} catch {
    Write-Host $($_.Exception.Message) -ForegroundColor Red
    exit 1
}

if ($exitCode -notin $exitCodes) {
     Write-Host "Unexpected exit code: $exitCode" -ForegroundColor Red
} else {
    Write-Host "Installation complete with exit code $exitCode"
}
exit $exitCode