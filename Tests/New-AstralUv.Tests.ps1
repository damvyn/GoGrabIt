#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-AstralUv.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-AstralUv.ps1"

        $script:FakeReply = [pscustomobject]@{
            tag_name = '0.9.5'
            assets = @(
                [pscustomobject]@{
                    name = 'uv-x86_64-pc-windows-msvc.zip.sha256'
                    browser_download_url = 'https://example.com/download/uv-x86_64-pc-windows-msvc.zip.sha256'
                },
                [pscustomobject]@{
                    name = 'uv-aarch64-pc-windows-msvc.zip'
                    browser_download_url = 'https://example.com/download/uv-aarch64-pc-windows-msvc.zip'
                },
                [pscustomobject]@{
                    name = 'uv-x86_64-pc-windows-msvc.zip'
                    browser_download_url = 'https://example.com/download/uv-x86_64-pc-windows-msvc.zip'
                }
            )
        }
    }

    Context 'Happy Path' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-RestMethod { return $FakeReply }

            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Call Invoke-RestMethod for correct API' {
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/astral-sh/uv/releases/latest'
            }
        }

        It 'Search pattern select only x64 zip asset' {
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://example.com/download/uv-x86_64-pc-windows-msvc.zip'
            }
        }

        It 'Create folder structure Vendor\Product-Version' {
            $expectedDir = Join-Path $TestDir 'Astral\uv-0.9.5'
            $expectedDir | Should -Exist
        }

        It 'Download zip to the Vendor\Product-Version' {
            $expectedFile = Join-Path $TestDir 'Astral\uv-0.9.5\uv-x86_64-pc-windows-msvc.zip'
            $expectedFile | Should -Exist
        }

        It 'Create Install.ps1 script' {
            $expectedInstallScript = Join-Path $TestDir 'Astral\uv-0.9.5\Install.ps1'
            $expectedInstallScript | Should -Exist
        }

        It 'Install.ps1 contains correct values' {
            $installScript = Join-Path $TestDir 'Astral\uv-0.9.5\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('uv-x86_64-pc-windows-msvc.zip'))
            $content | Should -Match 'Expand-Archive'
            $content | Should -Match ([regex]::Escape('C:\Program Files\astral.sh\uv'))
            $content | Should -Match 'HardLink'
            foreach ($exe in 'uv.exe', 'uvx.exe', 'uvw.exe') {
                $content | Should -Match ([regex]::Escape("'$exe'"))
            }
        }

        It 'Install.ps1 resolves $PSScriptRoot when it runs, not when generated' {
            $installScript = Join-Path $TestDir 'Astral\uv-0.9.5\Install.ps1'
            $content = Get-Content -Path $installScript -Raw
            $content | Should -Match ([regex]::Escape('"$PSScriptRoot\uv-x86_64-pc-windows-msvc.zip"'))
        }

        It 'Install.ps1 has no unreplaced placeholders' {
            $installScript = Join-Path $TestDir 'Astral\uv-0.9.5\Install.ps1'
            Get-Content -Path $installScript -Raw | Should -Not -Match '<FILE>|<EXE>|<PARAMS>|<ExitCodes>'
        }

        It 'Install.ps1 is a valid PowerShell script' {
            $installScript = Join-Path $TestDir 'Astral\uv-0.9.5\Install.ps1'
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($installScript, [ref]$null, [ref]$errors)
            $errors | Should -BeNullOrEmpty
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-RestMethod { return $FakeReply }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
            } -ParameterFilter { $OutFile }

            $expectedDir = Join-Path $ScriptDir 'Astral\uv-0.9.5'

            try {
                & $ScriptPath
                $expectedDir | Should -Exist
            }
            finally {
                Remove-Item -Path (Join-Path $ScriptDir 'Astral') -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'GitHub API failed' {
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

    Context 'Download link not found' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod {
                [pscustomobject]@{ tag_name = '0.9.5'; assets = @() }
            }
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
            Mock Invoke-WebRequest { throw 'The remote server returned an error: (404) Not Found.' }

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
                Set-Content -Path $OutFile -Value 'fake zip content' -Force
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
