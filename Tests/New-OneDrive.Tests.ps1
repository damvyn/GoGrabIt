#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-OneDrive.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-OneDrive.ps1"

        $script:FakeReply = [pscustomobject]@{
            Content = @'
<?xml version="1.0" encoding="utf-8"?>
<root>
  <update throttle="100" currentversion="26.189.0928.0009">
    <binary url="https://oneclient.sfx.ms/Win/Installers/26.189.0928.0009/x86/OneDriveSetup.exe" />
    <amd64binary url="https://oneclient.sfx.ms/Win/Installers/26.189.0928.0009/amd64/OneDriveSetup.exe" />
  </update>
  <update throttle="50" currentversion="26.195.1006.0007">
    <binary url="https://oneclient.sfx.ms/Win/Installers/26.195.1006.0007/x86/OneDriveSetup.exe" />
    <amd64binary url="https://oneclient.sfx.ms/Win/Installers/26.195.1006.0007/amd64/OneDriveSetup.exe" />
  </update>
</root>
'@
        }
        $script:ProductDir = 'Microsoft\OneDrive-26.189.0928.0009'
    }

    Context 'Happy Path' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-WebRequest { return $FakeReply } -ParameterFilter { -not $OutFile }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake installer content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Request the source' {
            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://g.live.com/1rewlive5skydrive/OneDriveProductionV2'
            }
        }

        It 'Download the expected installer' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://oneclient.sfx.ms/Win/Installers/26.189.0928.0009/amd64/OneDriveSetup.exe'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            Join-Path $TestDir $ProductDir | Should -Exist
        }

        It 'Download installer to the Vendor\Product-Version' {
            Join-Path $TestDir "$ProductDir\OneDriveSetup.exe" | Should -Exist
        }

        It 'Create Install.ps1 script' {
            Join-Path $TestDir "$ProductDir\Install.ps1" | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape('OneDriveSetup.exe'))
            $content | Should -Match ([regex]::Escape('/allusers'))
            $content | Should -Match ([regex]::Escape('/silent'))
        }

        It 'Install.ps1 does not use Start-Process -Wait and has a 10 minutes timeout' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Not -Match "'Wait'"
            $content | Should -Match ([regex]::Escape('$timeoutSeconds = 600'))
            $content | Should -Match ([regex]::Escape('WaitForExit($timeoutSeconds * 1000)'))
            $content | Should -Match ([regex]::Escape('Stop-Process -Id $process.Id'))
        }

        It 'Install.ps1 has product name and version' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape('Install OneDrive 26.189.0928.0009...'))
            $content | Should -Not -Match '<APPNAME>|<VERSION>|<EXE>|<PARAMS>|<FILE>|<ExitCodes>'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-WebRequest { return $FakeReply } -ParameterFilter { -not $OutFile }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake installer content' -Force
            } -ParameterFilter { $OutFile }

            try {
                & $ScriptPath
                Join-Path $ScriptDir $ProductDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'Microsoft') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Source request failed' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-WebRequest { throw 'Unable to connect to the remote server' }
            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Version or download link was not found' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-WebRequest { return [pscustomobject]@{ Content = ''; Links = @(); Headers = @{}; stable = @(); products = $null } }
            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Failed to create folder' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-WebRequest { return $FakeReply } -ParameterFilter { -not $OutFile }
            Mock New-Item { throw 'Access to the path is denied' }
            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Cannot download a file' {
        BeforeEach {
            $TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-WebRequest { return $FakeReply } -ParameterFilter { -not $OutFile }
            Mock Invoke-WebRequest { throw 'The remote server returned an error: (404) Not Found.' } -ParameterFilter { $OutFile }

            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }

    Context 'Cannot create install.ps1' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-WebRequest { return $FakeReply } -ParameterFilter { -not $OutFile }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake installer content' -Force
            } -ParameterFilter { $OutFile }
            Mock Out-File { throw 'Access to the path is denied' }

            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }
    }
}
