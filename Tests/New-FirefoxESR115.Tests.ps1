#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-FirefoxESR115.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-FirefoxESR115.ps1"

        $script:FakeReply = [pscustomobject]@{ FIREFOX_ESR = '153.6.0esr'; FIREFOX_ESR115 = '115.44.0esr' }
        $script:ProductDir = 'Mozilla\Firefox ESR 115-115.44.0'
    }

    Context 'Happy Path' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake installer content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Request the source' {
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://product-details.mozilla.org/1.0/firefox_versions.json'
            }
        }

        It 'Download the expected installer' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://releases.mozilla.org/pub/firefox/releases/115.44.0esr/win64/en-US/Firefox%20Setup%20115.44.0esr.exe'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            Join-Path $TestDir $ProductDir | Should -Exist
        }

        It 'Download installer to the Vendor\Product-Version' {
            Join-Path $TestDir "$ProductDir\Firefox Setup 115.44.0esr.exe" | Should -Exist
        }

        It 'Create Install.ps1 script' {
            Join-Path $TestDir "$ProductDir\Install.ps1" | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape('Firefox Setup 115.44.0esr.exe'))
            $content | Should -Match ([regex]::Escape('/S'))
            $content | Should -Match ([regex]::Escape('/DesktopShortcut=false'))
            $content | Should -Match ([regex]::Escape('/MaintenanceService=false'))
        }

        It 'Install.ps1 has product name and version' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape('Install Firefox ESR 115 115.44.0...'))
            $content | Should -Not -Match '<APPNAME>|<VERSION>|<EXE>|<PARAMS>|<FILE>|<ExitCodes>'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake installer content' -Force
            } -ParameterFilter { $OutFile }

            try {
                & $ScriptPath
                Join-Path $ScriptDir $ProductDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'Mozilla') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Source request failed' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod { throw 'Unable to connect to the remote server' }
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

            Mock Invoke-RestMethod { return [pscustomobject]@{ Content = ''; Links = @(); Headers = @{}; stable = @(); products = $null } }
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

            Mock Invoke-RestMethod { return $FakeReply }
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

            Mock Invoke-RestMethod { return $FakeReply }
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

            Mock Invoke-RestMethod { return $FakeReply }
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
