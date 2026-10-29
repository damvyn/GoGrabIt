#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

Describe 'New-WindowsDesktopRuntime.ps1' {
    BeforeAll {
        $script:RootPath = Split-Path -Path $PSScriptRoot -Parent
        $script:ScriptDir = Join-Path -Path $RootPath -ChildPath "Scripts"
        $script:ScriptPath = Join-Path -Path $ScriptDir -ChildPath "New-WindowsDesktopRuntime.ps1"

        $script:Versions = @{ '8.0' = '8.0.33'; '9.0' = '9.0.12'; '10.0' = '10.0.2' }
        $script:Replies = @{}
        foreach ($channel in $Versions.Keys) {
            $ver = $Versions[$channel]
            $script:Replies[$channel] = [pscustomobject]@{
                'latest-release' = $ver
                releases = @(
                    [pscustomobject]@{
                        'release-version' = "$channel.0"
                        windowsdesktop = [pscustomobject]@{
                            files = @([pscustomobject]@{ url = "https://example.com/old/windowsdesktop-runtime-$channel.0-win-x64.exe" })
                        }
                    },
                    [pscustomobject]@{
                        'release-version' = $ver
                        windowsdesktop = [pscustomobject]@{
                            files = @(
                                [pscustomobject]@{ url = "https://example.com/$ver/windowsdesktop-runtime-$ver-win-x86.exe" },
                                [pscustomobject]@{ url = "https://example.com/$ver/windowsdesktop-runtime-$ver-win-x64.exe" },
                                [pscustomobject]@{ url = "https://example.com/$ver/windowsdesktop-runtime-$ver-win-x64.zip" }
                            )
                        }
                    }
                )
            }
        }
    }

    Context 'Happy Path - all channels by default' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-RestMethod { return $Replies[($Uri -split '/')[-2]] }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir
        }

        It 'Request releases.json of every channel' {
            foreach ($channel in '8.0', '9.0', '10.0') {
                Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/$channel/releases.json"
                }
            }
        }

        It 'Create folder, installer and Install.ps1 for every channel' {
            foreach ($ver in $Versions.Values) {
                $dir = Join-Path $TestDir "Microsoft\Windows Desktop Runtime-$ver"
                $dir | Should -Exist
                Join-Path $dir "windowsdesktop-runtime-$ver-win-x64.exe" | Should -Exist
                Join-Path $dir 'Install.ps1' | Should -Exist
            }
        }

        It 'Select only the x64 exe' {
            Should -Invoke Invoke-WebRequest -Times 3 -Exactly -ParameterFilter { $Uri -like '*-win-x64.exe' }
        }

        It 'Install.ps1 contains correct values' {
            foreach ($ver in $Versions.Values) {
                $content = Get-Content -Path (Join-Path $TestDir "Microsoft\Windows Desktop Runtime-$ver\Install.ps1") -Raw
                $content | Should -Match ([regex]::Escape("windowsdesktop-runtime-$ver-win-x64.exe"))
                $content | Should -Match ([regex]::Escape('/install /quiet /norestart'))
                $content | Should -Match ([regex]::Escape("Install Windows Desktop Runtime $ver..."))
                $content | Should -Not -Match '<APPNAME>|<VERSION>|<EXE>|<PARAMS>|<FILE>|<ExitCodes>'
            }
        }
    }

    Context 'Happy Path - selected channel' {
        BeforeEach {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            $null = New-Item -Path $TestDir -ItemType:Directory -Force

            Mock Invoke-RestMethod { return $Replies[($Uri -split '/')[-2]] }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
            } -ParameterFilter { $OutFile }

            $script:Result = & $ScriptPath -Destination $TestDir -Channel '8.0', '10.0'
        }

        It 'Request only selected channels' {
            Should -Invoke Invoke-RestMethod -Times 2 -Exactly
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Uri -like '*/9.0/*' }
        }

        It 'Create folders only for selected channels' {
            Join-Path $TestDir 'Microsoft\Windows Desktop Runtime-8.0.33' | Should -Exist
            Join-Path $TestDir 'Microsoft\Windows Desktop Runtime-10.0.2' | Should -Exist
            Join-Path $TestDir 'Microsoft\Windows Desktop Runtime-9.0.12' | Should -Not -Exist
        }
    }

    Context 'Not supported channel' {
        It 'Throw a parameter validation error' {
            $TestDir = Join-Path -Path $TestDrive -ChildPath $((new-guid).guid)
            { & $ScriptPath -Destination $TestDir -Channel '7.0' } | Should -Throw
        }
    }

    Context 'Call without -Destination' {

        It 'Use $PSScriptRoot as default destination root' {
            Mock Invoke-RestMethod { return $Replies[($Uri -split '/')[-2]] }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
            } -ParameterFilter { $OutFile }

            try {
                & $ScriptPath -Channel '8.0'
                Join-Path $ScriptDir 'Microsoft\Windows Desktop Runtime-8.0.33' | Should -Exist
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

    Context 'Source request failed for one channel' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod {
                if ($Uri -like '*/9.0/*') { throw 'Unable to connect to the remote server' }
                return $Replies[($Uri -split '/')[-2]]
            }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
            } -ParameterFilter { $OutFile }
            & $ScriptPath -Destination $TestDir
            $script:exitCode = $LASTEXITCODE
        }

        It 'Return 1' {
            $exitCode | Should -Be 1
        }

        It 'Still build the other channels' {
            Join-Path $TestDir 'Microsoft\Windows Desktop Runtime-8.0.33\Install.ps1' | Should -Exist
            Join-Path $TestDir 'Microsoft\Windows Desktop Runtime-10.0.2\Install.ps1' | Should -Exist
        }
    }

    Context 'Download link was not found' {
        BeforeEach {
            $script:TestDir = Join-Path $TestDrive $((new-guid).guid)
            New-Item -Path $TestDir -ItemType Directory -Force | Out-Null

            Mock Invoke-RestMethod {
                return [pscustomobject]@{ 'latest-release' = '8.0.33'; releases = @() }
            }
            & $ScriptPath -Destination $TestDir -Channel '8.0'
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

            Mock Invoke-RestMethod { return $Replies[($Uri -split '/')[-2]] }
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

            Mock Invoke-RestMethod { return $Replies[($Uri -split '/')[-2]] }
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

            Mock Invoke-RestMethod { return $Replies[($Uri -split '/')[-2]] }
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                Set-Content -Path $OutFile -Value 'fake exe content' -Force
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
