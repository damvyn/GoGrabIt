#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-AdobeReader.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-AdobeReader.ps1"

        $script:FakeReply = [pscustomobject]@{
            products = [pscustomobject]@{
                reader = @(
                    [pscustomobject]@{ displayName = 'Reader 2026.002.22031 MUI for Windows-32bit'; version = '26.002.22031' },
                    [pscustomobject]@{ displayName = 'Reader 2026.002.22031 MUI for Windows-64bit (Recommended)'; version = '26.002.22031' }
                )
            }
        }
        $script:FakeDownload = [pscustomobject]@{
            downloadURL = 'https://example.com/acrobat/AcroRdrDCx642600222031_MUI.exe'
        }
        $script:ProductDir = 'Adobe\Adobe Reader-26.002.22031'
    }

    Context 'Happy Path' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-RestMethod { return $FakeReply } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/products*' }
            Mock Invoke-RestMethod { return $FakeDownload } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/downloadUrl*' }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake installer content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Request the source' {
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq 'https://rdc.adobe.io/reader/products?lang=mui&site=otherversions&os=Windows%2011&preInstalled=&api_key=dc-get-adobereader-cdn'
            }
        }

        It 'Download the expected installer' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/acrobat/AcroRdrDCx642600222031_MUI.exe'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            Join-Path $TestDir $ProductDir | Should -Exist
        }

        It 'Download installer to the Vendor\Product-Version' {
            Join-Path $TestDir "$ProductDir\AcroRdrDCx642600222031_MUI.exe" | Should -Exist
        }

        It 'Create Install.ps1 script' {
            Join-Path $TestDir "$ProductDir\Install.ps1" | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape('AcroRdrDCx642600222031_MUI.exe'))
            $content | Should -Match ([regex]::Escape('-sfx_nu /sALL'))
            $content | Should -Match ([regex]::Escape('EULA_ACCEPT=YES'))
            $content | Should -Match ([regex]::Escape('DISABLE_ARM_SERVICE_INSTALL=1'))
        }

        It 'Install.ps1 has product name and version' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape('Install Adobe Reader 26.002.22031...'))
            $content | Should -Not -Match '<APPNAME>|<VERSION>|<EXE>|<PARAMS>|<FILE>|<ExitCodes>'
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-RestMethod { return $FakeReply } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/products*' }
            Mock Invoke-RestMethod { return $FakeDownload } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/downloadUrl*' }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake installer content' -Force
            } -ParameterFilter { $OutFile }

            try {
                & $ScriptPath
                Join-Path $ScriptDir $ProductDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'Adobe') -Recurse -Force -ErrorAction SilentlyContinue
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

            Mock Invoke-RestMethod { return $FakeReply } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/products*' }
            Mock Invoke-RestMethod { return $FakeDownload } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/downloadUrl*' }
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

            Mock Invoke-RestMethod { return $FakeReply } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/products*' }
            Mock Invoke-RestMethod { return $FakeDownload } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/downloadUrl*' }
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

            Mock Invoke-RestMethod { return $FakeReply } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/products*' }
            Mock Invoke-RestMethod { return $FakeDownload } -ParameterFilter { $Uri -like 'https://rdc.adobe.io/reader/downloadUrl*' }
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
