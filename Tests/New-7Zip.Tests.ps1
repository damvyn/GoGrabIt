Import-Module 'C:\Dev\Projects\GoGrabIt\Tests\Pester\6.1.0\Pester.psm1' -Force

$scriptPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Scripts\New-7Zip.ps1'

Describe 'New-7Zip.ps1' {
    BeforeEach {
        $global:TestDestination = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
        $global:FakeRelease = [pscustomobject]@{
            tag_name = 'v27.00'
            assets = @(
                [pscustomobject]@{
                    Name = '7z2407-x64.msi'
                    browser_download_url = 'https://example.com/7z2407-x64.msi'
                }
            )
        }

        Mock Invoke-RestMethod {
            return $global:FakeRelease
        }

        Mock Invoke-WebRequest {
            param(
                [Parameter(Mandatory = $true)] [string]$OutFile
            )

            $directory = Split-Path -Path $OutFile -Parent
            if (-not (Test-Path -Path $directory)) {
                $null = New-Item -Path $directory -ItemType Directory -Force
            }

            [System.IO.File]::WriteAllBytes($OutFile, [byte[]](0x00, 0x01, 0x02, 0x03))
        }
    }

    It 'creates the expected output folder, downloads the installer, and writes Install.ps1' {
        & $scriptPath -Destination $global:TestDestination

        $versionDir = Join-Path -Path $global:TestDestination -ChildPath 'Igor Pavlov\7-Zip-27.00'
        $installerPath = Join-Path -Path $versionDir -ChildPath '7z2407-x64.msi'
        $installScriptPath = Join-Path -Path $versionDir -ChildPath 'Install.ps1'

        Test-Path -Path $versionDir | Should -BeTrue
        Test-Path -Path $installerPath | Should -BeTrue
        Test-Path -Path $installScriptPath | Should -BeTrue

        $installScriptContent = Get-Content -Path $installScriptPath -Raw
        $installScriptContent | Should -Match 'msiexec'
        $installScriptContent | Should -Match 'ALLUSERS=1'
        $installScriptContent | Should -Match '7z2407-x64\.msi'
    }

    It 'warns clearly when the GitHub release has no matching asset' {
        $global:FakeRelease = [pscustomobject]@{
            tag_name = 'v27.00'
            assets = @(
                [pscustomobject]@{
                    Name = 'setup.exe'
                    browser_download_url = 'https://example.com/setup.exe'
                }
            )
        }

        $output = & $scriptPath -Destination $global:TestDestination 2>&1

        $output | Should -Match 'No asset matched'
    }
}
