# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

GoGrabIt is a collection of **standalone** PowerShell scripts, each of which downloads the latest installer for one piece of software and generates a silent `Install.ps1` next to it. There is no module, no shared library, and no dependency between scripts — each one is meant to be downloaded and run on its own (see ReadMe.md for the end-user usage model).

## Structure

- `Scripts/New-<App>.ps1` — one script per application (e.g. `New-7Zip.ps1`, `New-Notepad++.ps1`).
- `Tests/New-<App>.Tests.ps1` — a matching Pester test file for every script, 1:1 by name. A new script always gets a new test file.
- `.github/workflows/RunTests.yaml` — CI: installs Pester and runs the full `Tests/` suite on `windows-latest` for every push/PR to `main`.

## The New-<App>.ps1 template

Every script in `Scripts/` follows the same shape. When adding a new one, copy the closest existing script (e.g. `New-7Zip.ps1`) and adjust, rather than writing from scratch:

1. `[CmdletBinding()] param([string]$Destination)` — `$RootPath` falls back to `$PSScriptRoot` when `-Destination` isn't given.
2. A product-info block of plain variables: `$ProductName`, `$VendorName`, `$ProductUrl`, `$SearchPattern`, `$InstallParams`, `$ExitCodes`.
3. Resolve the latest version and a direct download URL. **The source is per-vendor and not always GitHub** — existing scripts call the GitHub releases API (`Invoke-RestMethod` against `api.github.com/repos/.../releases/latest`, version parsed from `tag_name`), but other vendors may need a direct/static URL, an HTML page scrape, or a different JSON API. Match whatever the vendor actually exposes.
4. Build the target path as `$RootPath\$VendorName\$ProductName-$Version\`.
5. Download the installer with `Invoke-WebRequest` (reusing the same `$Params` hashtable pattern as the version-resolution request: `UseBasicParsing`, `DisableKeepAlive`, `ErrorAction = 'Stop'`).
6. If the download is an archive (e.g. `.zip`), `Expand-Archive`, delete the archive, then locate the real installer file inside (see `New-Paint.Net.ps1`).
7. Generate `Install.ps1` from an inline here-string template with `<EXE>`, `<PARAMS>`, `<FILE>`, `<ExitCodes>` placeholders, filled in via `.Replace()` and written with `Out-File -Encoding utf8`. The generated script requires admin (`#Requires -RunAsAdministrator`) and runs `Start-Process -Wait -PassThru`, checking the exit code against `$ExitCodes`.

Conventions to preserve:
- Every external call (`Invoke-RestMethod`, `New-Item`, `Invoke-WebRequest`, `Expand-Archive`, `Out-File`, …) is wrapped in its own `try/catch`; on failure, `Write-Host " * $($_.Exception.Message)" -ForegroundColor Red` then `return 1`. Don't throw — the script must exit with `return 1` so tests can assert on the return value.
- `$ExitCodes` is a comma-separated **string** (e.g. `"0, 3010"`), not an array.
- Status output uses `Write-Host` with `" * "`-prefixed bullets, Yellow for the start banner, Red for errors, Green for the final "Done".
- `$InstallParams` embeds `$PSScriptRoot` as a literal string (single-quoted) — it's meant to be evaluated when the *generated* `Install.ps1` runs, not when the generator script runs.
- use camelCase for variables names and PaskalCase for arguments
- use $response variable for keeping data from Invoke-RestMethod and Invoke-WebRequest commands
- use $requestParams variable as splatting input for Invoke-RestMethod and Invoke-WebRequest
- inide script use exit instead of return
- return is allowed for functions only

## Tests

Pester 6.1.0 or newer. Each test file:
- Starts with `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }`.
- `Describe '<ScriptFileName>.ps1'` resolves `$ScriptPath` via `$PSScriptRoot` (Tests dir → parent → `Scripts`).
- Mocks every external call (`Invoke-RestMethod`, `Invoke-WebRequest`, `Expand-Archive`, `New-Item`, `Out-File`, …) — tests never hit the network.
- A `Happy Path` context runs the script against a `$TestDrive` temp dir and asserts the resulting folder structure, downloaded/extracted files, and generated `Install.ps1` content.
- One context per failure mode (API failure, folder-creation failure, download failure, extraction failure, install-script write failure), each mocking the relevant call to `throw` and asserting `$Result | Should -Be 1`.

Run the full suite the same way CI does:

```powershell
Install-Module -Name Pester -RequiredVersion 6.1.0 -Force -SkipPublisherCheck -Scope CurrentUser
Import-Module Pester -RequiredVersion 6.1.0
Invoke-Pester -Path .\Tests
```

Run a single test file with `Invoke-Pester -Path .\Tests\New-7Zip.Tests.ps1`.

## Linting

`PSScriptAnalyzerSettings.psd1` at the repo root excludes `PSAvoidUsingWriteHost`, since colored `Write-Host` status output is deliberate throughout the scripts. Run:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```
