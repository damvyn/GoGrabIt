#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-MicrosoftEdge.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-MicrosoftEdge.ps1"

        $script:FakeReply = @(
            [pscustomobject]@{
                Product = 'Beta'
                Releases = @(
                    [pscustomobject]@{ Platform = 'Windows'; Architecture = 'x64'; ProductVersion = '156.0.9999.1'
                        Artifacts = @([pscustomobject]@{ ArtifactName = 'msi'; Location = 'https://example.com/beta/MicrosoftEdgeBetaEnterpriseX64.msi' }) }
                )
            },
            [pscustomobject]@{
                Product = 'Stable'
                Releases = @(
                    [pscustomobject]@{ Platform = 'Windows'; Architecture = 'x64'; ProductVersion = '155.0.4300.10'
                        Artifacts = @([pscustomobject]@{ ArtifactName = 'msi'; Location = 'https://example.com/old/MicrosoftEdgeEnterpriseX64.msi' }) },
                    [pscustomobject]@{ Platform = 'Windows'; Architecture = 'x64'; ProductVersion = '156.0.4314.50'
                        Artifacts = @(
                            [pscustomobject]@{ ArtifactName = 'zip'; Location = 'https://example.com/new/edge.zip' },
                            [pscustomobject]@{ ArtifactName = 'msi'; Location = 'https://example.com/new/MicrosoftEdgeEnterpriseX64.msi' }
                        ) },
                    [pscustomobject]@{ Platform = 'Windows'; Architecture = 'x86'; ProductVersion = '156.0.4314.50'
                        Artifacts = @([pscustomobject]@{ ArtifactName = 'msi'; Location = 'https://example.com/x86/MicrosoftEdgeEnterpriseX86.msi' }) }
                )
            }
        )
        $script:ProductDir = 'Microsoft\Microsoft Edge-156.0.4314.50'
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
                $Uri -eq 'https://edgeupdates.microsoft.com/api/products'
            }
        }

        It 'Download the expected installer' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/new/MicrosoftEdgeEnterpriseX64.msi'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            Join-Path $TestDir $ProductDir | Should -Exist
        }

        It 'Download installer to the Vendor\Product-Version' {
            Join-Path $TestDir "$ProductDir\MicrosoftEdgeEnterpriseX64.msi" | Should -Exist
        }

        It 'Create Install.ps1 script' {
            Join-Path $TestDir "$ProductDir\Install.ps1" | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape('MicrosoftEdgeEnterpriseX64.msi'))
            $content | Should -Match ([regex]::Escape('ALLOWINSTALL=1'))
            $content | Should -Match ([regex]::Escape('DONOTCREATEDESKTOPSHORTCUT=true'))
            $content | Should -Match ([regex]::Escape('ALLUSERS=1'))
            $content | Should -Match ([regex]::Escape('/qn'))
            $content | Should -Match ([regex]::Escape('msiexec'))
        }

        It 'Install.ps1 has product name and version' {
            $content = Get-Content -Path (Join-Path $TestDir "$ProductDir\Install.ps1") -Raw
            $content | Should -Match ([regex]::Escape('Install Microsoft Edge 156.0.4314.50...'))
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
                Remove-Item -Path (Join-Path $ScriptDir 'Microsoft') -Recurse -Force -ErrorAction SilentlyContinue
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
