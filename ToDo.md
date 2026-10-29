# ToDo

Apps from `examples/` that have **no** `Scripts\New-<App>.ps1` / `Tests\New-<App>.Tests.ps1` yet (46 entries).
For each one this file records how the example script finds the **version** and the **download link**, and what makes it
hard to port to the standalone `New-<App>.ps1` template (`templates\new-software.ps1`).

> **How to read this file**
> * Everything below comes from *reading the example scripts*. Nothing was downloaded or installed to produce it.
> * Only items marked **(verified)** were checked against the live site while converting the other apps.
> * "Template" = `templates\new-software.ps1`. It needs the **version and a direct download URL before** anything is downloaded
>   (`Root\Vendor\Product-Version\`), then downloads the file, then writes `Install.ps1`.

## Why these were not converted

| Code | Problem | What it means for the template |
|------|---------|--------------------------------|
| **DL-FIRST** | The version is not published anywhere the example reads. It is taken from the *downloaded file* (`VersionInfo.ProductVersion`) or from MSI properties (`Get-MsiProps`, COM `WindowsInstaller.Installer`) after the download. | Folder name needs the version, so the file has to be downloaded to a temp folder first and moved. The template has no such step. Decision taken: **do not do it**. Alternative: find a separate version source (vendor API, winget manifest, release notes). |
| **SCRAPE** | Version and/or link are scraped from an HTML page (link lists, regex over page text, JS embedded in the page). | Doable but breaks whenever the page layout changes. Needs `Invoke-WebRequest` instead of `Invoke-RestMethod` (see the HTML-scrape tests of `New-VLC` and `Problems/Tests/New-Nmap.Tests.ps1`). |
| **REDIRECT** | The link is read from the `Location` header with `-MaximumRedirection 0`. | **(verified, with another site)** in PowerShell 7 this throws `302 (Found)` even with `-ErrorAction Ignore`; PowerShell 5.1 behaves differently. Needs a `try/catch` or `-SkipHttpErrorCheck` and a test on both versions. |
| **MULTI-STEP** | Several chained requests (API list, then API details, then link), or several files per package. | More code than the template's single request; each step needs its own error handling and tests. |
| **LICENSE** | Commercial / trial / login-gated product, license key, transform file or settings file that is not public. | The silent install is not reproducible from a public download alone. |
| **NOT-INSTALLER** | The result is not a silent `.exe` / `.msi` (MSIX, bootstrapper, zip with several installers, post-install steps). | `Install.ps1` from `installtemplate.ps1` does not fit; needs a custom install template (like `New-ResInsight` or `New-AstralUv`). |
| **FIXED-YEAR** | A year/major number is hard-coded in the URL. | Needs a manual bump each year or a second source for the current number. |
| **PORTAL** | Uses something that exists only in the original Cloud Portal environment. | Cannot be reproduced standalone. |

---

## 1. Version only available inside the downloaded file (DL-FIRST)

These have a fixed "latest" URL and no version source. The example downloads first, then reads the version.

| App | Example | Download link | Version | Notes |
|-----|---------|---------------|---------|-------|
| TeamViewer | `New-TeamViewerPackage.ps1` | `https://dl.teamviewer.com/download/TeamViewer_Setup.exe` | `VersionInfo.ProductVersionRaw`, joined as `Major.Minor.Build` | silent: `/S /norestart` |
| TreeSize Free | `New-JamTreeSizeFreePackage.ps1` | `https://downloads.jam-software.de/treesize_free/TreeSizeFreeSetup.exe` | `VersionInfo.ProductVersion` | silent: Inno Setup switches |
| TreeSize (paid) | `New-JamTreeSizePackage.ps1` | `https://downloads.jam-software.de/treesize/TreeSize-Setup.exe` | `VersionInfo.ProductVersion` | **LICENSE**: license key goes to `/PASSWORD=`; without a key it installs in DEMO mode |
| Miniconda | `New-MinicondaPackage.ps1` | `https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe` | `VersionInfo.ProductVersion` | `/S /NoRegistry=1 /InstallationType=AllUsers ...`; the example links Anaconda's terms of service |
| TeraCopy | `New-TeraCopyPackage.ps1` | `https://www.codesector.com/files/teracopy.exe` | `VersionInfo.ProductVersion` | silent: `/exenoui /exenoupdates /qn` |
| Power BI Desktop | `New-PowerBIPackage.ps1` | `https://download.microsoft.com/download/8/8/0/880BCA75-79DD-466A-927D-1ABF1F5454B0/PBIDesktopSetup_x64.exe` | `VersionInfo.ProductVersion` | the URL contains a GUID, so it could change. My scan did not find the silent switches, re-read the example before porting |
| Power BI Report Builder | `New-PowerBIReportBuilderPackage` (no `.ps1` extension) | `https://download.microsoft.com/download/a/2/e/a2ea07b5-5a65-41d7-9ac0-b46ac953ab63/PowerBIReportBuilder.msi` | MSI property `ProductVersion` (`Get-MsiProps`, COM) | GUID in the URL |
| Box Tools | `New-BoxToolsPackage.ps1` | `https://e3.boxcdn.net/box-installers/boxedit/win/currentrelease/BoxToolsInstaller-AdminInstall.msi` | MSI property `ProductVersion` | `ALLUSERS=1 REBOOT=ReallySuppress /qn` |
| UltraEdit | `New-UltraEditPackage.ps1` | `https://downloads.ultraedit.com/main/ue/win/ue_english_64.msi` | MSI property `ProductVersion` | **LICENSE** (commercial) |
| UltraCompare | `New-UltraComparePackage.ps1` | `https://downloads.ultraedit.com/main/uc/win/uc_english_64.msi` | MSI property `ProductVersion` | **LICENSE** (commercial) |
| PC-PUMP | `New-PcPumpPackage.ps1` | scraped from `https://www.cfertech.com/pc-pump/user-area/`: links matching `^https.*download.*exe$` | `VersionInfo.ProductVersion` of the downloaded exe | **SCRAPE + LICENSE**: "user-area" suggests a gated page, not checked. Installer wraps an MSI: `/s /v"/qn ..."` |
| Power Automate Desktop | `New-PowerAutomateDesktopPackage.ps1` | `https://go.microsoft.com/fwlink/?linkid=2102613`, redirect read from the `Location` header (**REDIRECT**) | `VersionInfo.ProductVersion` of the downloaded exe | silent: `-Silent -Install -ACCEPTEULA`; the example also sets registry values to disable auto-update after install, which does not fit `installtemplate.ps1` |
| Visual C++ Redistributable 2015-2022 | `New-VcRedist2015+Package.ps1` | `https://aka.ms/vs/17/release/vc_redist.x64.exe` and `.../vc_redist.x86.exe` | `VersionInfo.ProductVersion` of each file | two packages (x64 and x86) from one script; `aka.ms` is a redirect |
| FSLogix Apps Agent | `New-FsLogixPackage.ps1` | `https://aka.ms/fslogix_download` (a zip, saved as `FSLogix_Apps.zip`) | `ProductVersion` of `FSLogixAppsSetup.exe` found inside the extracted zip | **NOT-INSTALLER**: zip with several installers; `aka.ms` redirect; `/install /quiet /norestart` |
| Inkscape | `New-InkscapePackage.ps1` | **REDIRECT**: `https://inkscape.org/release/` redirects to the current release page, then `<release>windows/64-bit/msi/dl/`, then the first `*.msi` link | MSI property `ProductVersion` after the download | **(verified)** the 302 handling throws in PowerShell 7. The release path may contain the version, which would remove DL-FIRST, but that was not confirmed |

**Possible way forward for the whole group:** look for an independent version feed (vendor release notes, winget manifests in
`microsoft/winget-pkgs`, Chocolatey/Scoop manifests) and resolve the version from there. Not investigated yet.

---

## 2. Versions and links from HTML pages (SCRAPE)

| App | Example | Where | How the example does it | Problems |
|-----|---------|-------|--------------------------|----------|
| Agisoft Metashape | `New-MetaShapePackage.ps1` | `https://www.agisoft.com/downloads/installer/` | links `*metashape_*_x64.msi`, first one; version = file name with `_` replaced by `.` | **LICENSE** (trial/commercial). Version taken from the file name only |
| Agisoft Viewer | `New-AgisoftViewerPackage.ps1` | same page | links `*viewer_*_x64.msi`, same parsing | same page and parsing as above |
| Agisoft DeLighter | `New-DeLighterPackage.ps1` | same page | links `*delighter_*_x64.msi`, same parsing | same page and parsing as above |
| CS Browser (S3 Browser) | `New-CSBrowserPackage.ps1` | version from `https://s3browser.com/rss.xml`, link from `https://s3browser.com/download.aspx` | regex `\d+(\.\d+)+` on the first RSS item title; first `*.msi` link on the page | two different sources must agree; example vendor is "Netsdk Software FZE" |
| CutePDF Writer | `New-CutePDFWriterPackage.ps1` | `https://www.cutepdf.com/products/cutepdf/writer.asp` | version from page text `Ver. x.y.z;`; link is the fixed `https://www.cutepdf.com/download/CuteWriter.exe` | page text format; installer is Inno Setup (`/VERYSILENT`) |
| DUG Insight | `New-DugInsightPackage.ps1` | `https://dug.com/dug-insight/download-resources/` | regex over page text for `DUG Insight x.y (build n)` and `https:.*_x64.msi` | **LICENSE**; the build number is also needed; page text format |
| FME Form | `New-FMEFormPackage.ps1` | `https://fme.safe.com/downloads` | extracts the JavaScript array passed to `download_picker(` with a hand-written bracket/quote parser, then converts it to JSON | very fragile; **LICENSE** (commercial); install params are built as an array |
| Glex Energy | `New-GlexEnergyPackage.ps1` | `https://glex.no/download` | regex `Latest release: <ver>`; link matching `.*Windows.*\.exe$` | proprietary; the example has a leftover `$CurrentRelease.href` line |
| Google Earth Pro | `New-GoogleEarthPackage.ps1` | `https://support.google.com/earth/answer/168344` | links matching `googleearthprowin-<ver>-x64.exe`, highest version | support page layout; silent param is `OMAHA=1` |
| Mountain Duck | `New-MountainduckPackage.ps1` | `https://mountainduck.io/` | link `*.msixbundle`; version from file name | **NOT-INSTALLER**: MSIX bundle, installed with `Add-AppxPackage -Register`; license needed for full use |
| PL/SQL Developer | `New-PLSQLDeveloperPackage.ps1` | `https://www.allroundautomations.com/try-it-free/` | link `*plsqldev*x64.msi`; regex `PL/SQL Developer Evaluation ... Version x.y` | **LICENSE** (evaluation download) |
| Cisco Webex | `New-CiscoWebexPackage.ps1` | version from `https://help.webex.com/en-us/article/8dmbcr`; link fixed: `https://binaries.webex.com/WebexOfclDesktop-Win-64-Gold/Webex.msi` | regex `Windows—<ver></p>` (contains an em dash) on the release-notes article | the fixed MSI may not match the version in the article; page text and non-ASCII character in the regex |
| WellCad Reader | `New-WellCadReaderPackage.ps1` | `https://downloads.wellcad.com/wellcad/reader` | **REDIRECT**, same as above | same as above |

---

## 3. JSON / XML / text APIs (doable, but more than one request)

| App | Example | Source | How the example does it | Problems |
|-----|---------|--------|--------------------------|----------|
| Edge WebView2 Runtime | `New-EdgeWebView2RuntimePackage.ps1` | version from the same Edge API; download `https://go.microsoft.com/fwlink/?linkid=2124701` | the version comes from the API, the file from an `fwlink` redirect | the fwlink gives a file name only after the redirect; whether it is the 64-bit standalone installer was not checked. Silent: `/silent /install` |
| EndNote | `New-EndNotePackage.ps1` | `https://download.endnote.com/updates/22.0/EN22WinUpdates.xml` | highest `updateTo` of the `build` elements | **FIXED-YEAR + LICENSE**: installer is `https://download.endnote.com/downloads/2025/EN2025Inst.msi`, so the year must be changed by hand |
| Oracle Java 8 JRE | `New-OracleJRE8Package.ps1` | `https://javadl-esd-secure.oracle.com/update/1.8.0/map-m-1.8.0.xml` | feed gives a second XML; `java-update.information` for `lang = en` has `url` and `version`; version is built as `8.<update>` | two chained requests; Oracle licensing terms; long install property list (`INSTALL_SILENT=1 STATIC=0 AUTO_UPDATE=0 ...`) |
| VMware Tools 12 | `New-VmWareTools12Package.ps1` | `https://packages.vmware.com/tools/versions` | text file, skips 17 header lines, stops at the `# VMTools versions EOGS` marker, splits each line; URL template `.../tools/releases/#version/x64/VMware-tools-#version-#build-x64.exe` | the build number is needed too; the text format is not a stable API; output of the parser was not checked |
| VMware Tools 13 | `New-VmWareTools13Package.ps1` | same file | same parser; URL template has `windows/` in the path: `.../#version/windows/x64/...` | same as above |
| SQL Server ODBC Driver 17 | `New-SQLODBCDriver17Package.ps1` | `https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server` | regex `Release number: 17.x.x.x` on the page; link whose `OuterHTML` contains the text `Download Microsoft ODBC Driver 17 for SQL Server (x64)` | depends on page text and layout; the link is an `fwlink` redirect; needs `IACCEPTMSODBCSQLLICENSETERMS=YES` |
| SQL Server ODBC Driver 18 | `New-SQLODBCDriver18Package.ps1` | same page | same, with `18.` | same as above |
| OLE DB Driver 18 for SQL Server | `New-SQLOLEDBDriver18Package.ps1` | `https://learn.microsoft.com/en-us/sql/connect/oledb/release-notes-for-oledb-driver-for-sql-server` | first `<h2>` with `18.x.y`; then string positions between that heading and the text `Download x64 installer` to cut out the link | most fragile of the group: character positions in the HTML. `IACCEPTMSOLEDBSQLLICENSETERMS=YES` |
| OLE DB Driver 19 for SQL Server | `New-SQLOLEDBDriver19Package.ps1` | same page | regex `19.x.y`; link whose `OuterHTML` matches `Download x64* installer`, first match | page layout dependent |

---

## 4. Multi-step, licensed or non-standard installers

| App | Example | Source | How the example does it | Problems |
|-----|---------|--------|--------------------------|----------|
| Adobe Acrobat (x64) | `New-AdobeAcrobatX64Package.ps1` | version from `https://rdc.adobe.io/reader/products?...site=enterprise...`; media `https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip` | version from the `64bit` Reader entry; downloads the trial zip, expands it, runs `Setup.exe` | **LICENSE** (trial media); **NOT-INSTALLER**: zip with `Setup.exe` |
| Adobe Acrobat (update patch) | `New-AdobeAcrobatPackage.ps1` | version `products.reader[0].version` from the enterprise API | patch URL built as `https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/<ver without dots>/AcrobatDCUpd<ver without dots>.msp`; the example also expands a `Media.zip` base package and runs `setup.exe` with many properties | **LICENSE + NOT-INSTALLER**: an MSP update only works on top of a base install; where `Media.zip` comes from was not confirmed |
| Omnissa Horizon Client | `New-OmnissaHorizonClient.ps1` | `https://customerconnect.omnissa.com/channel/public/api/v1.0/...` | step 1: `getRelatedDLGList` to find the "Client for Windows" group, its `code`, `productId`, `releasePackageId`; step 2: `dlg/details` for the file `*Horizon-Client*.exe` | **MULTI-STEP**; undocumented API; install uses `ADDLOCAL`/`REMOVE` feature lists |
| Foxit PDF Reader | `New-FoxitReaderPackage.ps1` | `https://www.foxit.com/downloads/` | an `HttpWebRequest` reads the `token` cookie, then it calls `.../foxit-api/form/showDownloadForm/...` with `Authorization: Bearer` and `.../form/latest/?product=Foxit-Reader&...` | **MULTI-STEP + cookie/token** scraping, which can stop working without notice |
| Microsoft Teams (new) | `New-TeamsPackage.ps1` | `https://config.teams.microsoft.com/config/v1/MicrosoftTeams/1415_1.0.0.0?...` | `BuildSettings.WebView2Canary.x64`: `latestVersion` and `buildLink` (an MSIX) plus `https://statics.teams.cdn.office.net/production-teamsprovision/lkg/teamsbootstrapper.exe` | **NOT-INSTALLER**: installed with `teamsbootstrapper.exe -p -o <msix>` or `DISM /Add-ProvisionedAppxPackage`; the example also handles an Outlook add-in MSI; the JSON key name `WebView2Canary` looks odd and was not checked |
| TechSmith Snagit | `New-SnagItPackage.ps1` | `https://www.techsmith.com/api/v/1/products/getallversions/12` then `.../getversioninfo/<VersionID>` | version `Major.Minor.Maintenance`; the `.msi` entry of `AlternateDownloadInformation` gives `RelativePath` + `Name`, added to `http://download.techsmith.com` | **LICENSE + MULTI-STEP**: zip with MSI, needs `snagit.mst` and a license key (`TSC_SOFTWARE_KEY`) |
| Bluebeam Revu | `New-BluebeamRevuPackage.ps1` | GitHub contents API of `microsoft/winget-pkgs` (Revu and OCR folders) | walks major version folder, version folder, `*.installer.yaml`, then reads `InstallerUrl` from the raw YAML; same for the OCR package | **LICENSE + MULTI-STEP**: two MSIs in one zip, `TRANSFORMS=:1033`, `BB_SERIALNUMBER="TRIAL"`; depends on winget folder layout and unauthenticated GitHub API limits |
| 3Dconnexion 3DxWare | `New-3DxWarePackage.ps1` | `https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/3/3Dconnexion/3DxWare/10` | last entry name is the version; the raw `...installer.yaml` is searched for `https://download.3dconnexion.com...*.exe` | depends on the winget manifest; install uses `LoadSettings="3DxWareSettings.xml"` which is **not public** (**LICENSE/PORTAL**) |
| Autodesk Navisworks Freedom | `New-NawisworkFreedomPackage.ps1` | winget manifest `Autodesk.NavisworksFreedom.2027.installer.yaml` | URL read from the manifest | **FIXED-YEAR + PORTAL**: the year 2027 is hard-coded; it downloads `7za.zip` from the portal host (`$CloudPortalHost`) to unpack a self-extracting installer |

---

## Moved to `Problems/`

Scripts that were written and tested but cannot work unattended are kept in `Problems\Scripts` and `Problems\Tests`.
They are not listed in `ReadMe.md` and are not run by CI or `RunLocalTests.ps1` (both run only `Tests\`).

| App | Problem |
|-----|---------|
| Nmap | No silent installation. |
| Ghostscript | No silent installation (script and test were deleted earlier, see commit afbd7d7). |

---

## Summary of what is realistically portable next

* **Easy / low risk:** Edge WebView2 (after checking the fwlink).
* **Moderate:** Oracle JRE 8, Google Earth Pro, WellCad Reader (same redirect handling as WellCad).
* **Needs the download-first template variant (currently rejected):** everything in section 1.
* **Not portable without non-public inputs:** Bluebeam Revu, 3DxWare, Navisworks Freedom, Snagit, TreeSize, UltraEdit/UltraCompare, EndNote, PL/SQL Developer, DUG Insight, Glex Energy, Agisoft, FME Form, PC-PUMP.
