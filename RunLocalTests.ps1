Import-Module Pester

$config = New-PesterConfiguration
$config.Run.Path = '.\Tests'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true

Invoke-Pester -Configuration $config