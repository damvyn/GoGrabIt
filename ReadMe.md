## GoGrabIt🐰

### ❓What does it do?
**GoGrabit** downloads software and create simple silent installation scripts.

### ⚙️ How does it work?
I've started doing the module, but came to the conclusion that there is no need to reinvent the wheel in the world of WinGet, PatchMyPC, Chocolatey, Evergreen...

The benefit of this project is running a single script to the job without any installations and prerequisites.
Each script works independetly and there is no need to download everything.
By default, script creates next strusture
```
📁 <Your worwing folder>
 ├── 📄 New-Something.ps1
 └── 📁 <Vendor>
      └── 📁 <Product1-Version>
           ├── 📄 Setup.exe
           └── 📄 Install.ps1     
```
### ▶️ How do I run it?
Download the desired script and then
 * Call conext menu on it and select 'Run with PowerShell'
 * Start PowerShell change working location to a directory with script and run it. Example:
```powershell
cd $env:Userprofile\downloads
.\New-7Zip.ps1
```
 * In PowerShell it is possible to use **-Destination** parameter to change the path where to save installer
 ```powershell
.\New-7Zip.ps1 -Destination "C:\Software"
```
In this case the script creates foder **Software** if it is not present and puts data there:
```
📁 Software
 ├── 📄 New-7Zip.ps1
 └── 📁 Igor Pavlov
      └── 📁 7-Zip-v26.03
           ├── 📄 Setup.exe
           └── 📄 Install.ps1     
```
 * Use the **-Install** switch to install the product right after it is downloaded. The generated **Install.ps1** is run immediately, so start PowerShell as administrator:
```powershell
.\New-7Zip.ps1 -Install
```
It can be combined with **-Destination**. The installation prints its result as `[OK]` or `[FAIL] Error Code: <code>`.

> [!NOTE]
> Make sure the execution policy is RemoteSign or less strict
> You may need to unblock New-Something.ps1 in Properties.

### 📦 Available scripts

| App Name | Script | Test |
|----------|--------|------|
| 7-Zip | [New-7Zip.ps1](Scripts/New-7Zip.ps1) | [New-7Zip.Tests.ps1](Tests/New-7Zip.Tests.ps1) |
| Anaconda3 | [New-Anaconda.ps1](Scripts/New-Anaconda.ps1) | [New-Anaconda.Tests.ps1](Tests/New-Anaconda.Tests.ps1) |
| Arduino IDE | [New-ArduinoIDE.ps1](Scripts/New-ArduinoIDE.ps1) | [New-ArduinoIDE.Tests.ps1](Tests/New-ArduinoIDE.Tests.ps1) |
| Arelle | [New-Arelle.ps1](Scripts/New-Arelle.ps1) | [New-Arelle.Tests.ps1](Tests/New-Arelle.Tests.ps1) |
| AutoHotkey | [New-AutoHotkey.ps1](Scripts/New-AutoHotkey.ps1) | [New-AutoHotkey.Tests.ps1](Tests/New-AutoHotkey.Tests.ps1) |
| Azure CLI | [New-AzureCLI.ps1](Scripts/New-AzureCLI.ps1) | [New-AzureCLI.Tests.ps1](Tests/New-AzureCLI.Tests.ps1) |
| Azure Storage Explorer | [New-AzureStorageExplorer.ps1](Scripts/New-AzureStorageExplorer.ps1) | [New-AzureStorageExplorer.Tests.ps1](Tests/New-AzureStorageExplorer.Tests.ps1) |
| Chrome | [New-Chrome.ps1](Scripts/New-Chrome.ps1) | [New-Chrome.Tests.ps1](Tests/New-Chrome.Tests.ps1) |
| DBeaver Community | [New-DBeaver.ps1](Scripts/New-DBeaver.ps1) | [New-DBeaver.Tests.ps1](Tests/New-DBeaver.Tests.ps1) |
| Everything | [New-Everything.ps1](Scripts/New-Everything.ps1) | [New-Everything.Tests.ps1](Tests/New-Everything.Tests.ps1) |
| FileZilla Ftp Client | [New-FileZilla.ps1](Scripts/New-FileZilla.ps1) | [New-FileZilla.Tests.ps1](Tests/New-FileZilla.Tests.ps1) |
| Firefox | [New-Firefox.ps1](Scripts/New-Firefox.ps1) | [New-Firefox.Tests.ps1](Tests/New-Firefox.Tests.ps1) |
| Firefox ESR | [New-FirefoxESR.ps1](Scripts/New-FirefoxESR.ps1) | [New-FirefoxESR.Tests.ps1](Tests/New-FirefoxESR.Tests.ps1) |
| Flameshot | [New-Flameshot.ps1](Scripts/New-Flameshot.ps1) | [New-Flameshot.Tests.ps1](Tests/New-Flameshot.Tests.ps1) |
| FreeCad | [New-FreeCad.ps1](Scripts/New-FreeCad.ps1) | [New-FreeCad.Tests.ps1](Tests/New-FreeCad.Tests.ps1) |
| GhostScript | [New-GhostScript.ps1](Scripts/New-GhostScript.ps1) | [New-GhostScript.Tests.ps1](Tests/New-GhostScript.Tests.ps1) |
| Git | [New-Git.ps1](Scripts/New-Git.ps1) | [New-Git.Tests.ps1](Tests/New-Git.Tests.ps1) |
| Graphviz | [New-Graphviz.ps1](Scripts/New-Graphviz.ps1) | [New-Graphviz.Tests.ps1](Tests/New-Graphviz.Tests.ps1) |
| Greenshot | [New-Greenshot.ps1](Scripts/New-Greenshot.ps1) | [New-Greenshot.Tests.ps1](Tests/New-Greenshot.Tests.ps1) |
| Handbrake | [New-Handbrake.ps1](Scripts/New-Handbrake.ps1) | [New-Handbrake.Tests.ps1](Tests/New-Handbrake.Tests.ps1) |
| HeidiSQL | [New-HeidiSQL.ps1](Scripts/New-HeidiSQL.ps1) | [New-HeidiSQL.Tests.ps1](Tests/New-HeidiSQL.Tests.ps1) |
| ImageGlass | [New-ImageGlass.ps1](Scripts/New-ImageGlass.ps1) | [New-ImageGlass.Tests.ps1](Tests/New-ImageGlass.Tests.ps1) |
| LibreCAD | [New-LibreCad.ps1](Scripts/New-LibreCad.ps1) | [New-LibreCad.Tests.ps1](Tests/New-LibreCad.Tests.ps1) |
| Nmap | [New-Nmap.ps1](Scripts/New-Nmap.ps1) | [New-Nmap.Tests.ps1](Tests/New-Nmap.Tests.ps1) |
| Node.js | [New-NodeJs.ps1](Scripts/New-NodeJs.ps1) | [New-NodeJs.Tests.ps1](Tests/New-NodeJs.Tests.ps1) |
| Notepad++ | [New-Notepad++.ps1](Scripts/New-Notepad%2B%2B.ps1) | [New-Notepad++.Tests.ps1](Tests/New-Notepad%2B%2B.Tests.ps1) |
| PaintDotNet | [New-Paint.Net.ps1](Scripts/New-Paint.Net.ps1) | [New-Paint.Net.Tests.ps1](Tests/New-Paint.Net.Tests.ps1) |
| Path Copy Copy | [New-PathCopyCopy.ps1](Scripts/New-PathCopyCopy.ps1) | [New-PathCopyCopy.Tests.ps1](Tests/New-PathCopyCopy.Tests.ps1) |
| PDFsamBasic | [New-PDFsamBasic.ps1](Scripts/New-PDFsamBasic.ps1) | [New-PDFsamBasic.Tests.ps1](Tests/New-PDFsamBasic.Tests.ps1) |
| PeaZip | [New-PeaZip.ps1](Scripts/New-PeaZip.ps1) | [New-PeaZip.Tests.ps1](Tests/New-PeaZip.Tests.ps1) |
| Power Toys | [New-PowerToys.ps1](Scripts/New-PowerToys.ps1) | [New-PowerToys.Tests.ps1](Tests/New-PowerToys.Tests.ps1) |
| PowerShell | [New-PowerShell.ps1](Scripts/New-PowerShell.ps1) | [New-PowerShell.Tests.ps1](Tests/New-PowerShell.Tests.ps1) |
| PuTTY | [New-PuTTY.ps1](Scripts/New-PuTTY.ps1) | [New-PuTTY.Tests.ps1](Tests/New-PuTTY.Tests.ps1) |
| PyCharm | [New-PyCharm.ps1](Scripts/New-PyCharm.ps1) | [New-PyCharm.Tests.ps1](Tests/New-PyCharm.Tests.ps1) |
| Python | [New-Python.ps1](Scripts/New-Python.ps1) | [New-Python.Tests.ps1](Tests/New-Python.Tests.ps1) |
| QGIS | [New-QGIS.ps1](Scripts/New-QGIS.ps1) | [New-QGIS.Tests.ps1](Tests/New-QGIS.Tests.ps1) |
| ResInsight | [New-ResInsight.ps1](Scripts/New-ResInsight.ps1) | [New-ResInsight.Tests.ps1](Tests/New-ResInsight.Tests.ps1) |
| RStudio Desktop | [New-RStudio.ps1](Scripts/New-RStudio.ps1) | [New-RStudio.Tests.ps1](Tests/New-RStudio.Tests.ps1) |
| ShareX | [New-ShareX.ps1](Scripts/New-ShareX.ps1) | [New-ShareX.Tests.ps1](Tests/New-ShareX.Tests.ps1) |
| Sourcetree | [New-SourceTree.ps1](Scripts/New-SourceTree.ps1) | [New-SourceTree.Tests.ps1](Tests/New-SourceTree.Tests.ps1) |
| Spyder | [New-Spyder.ps1](Scripts/New-Spyder.ps1) | [New-Spyder.Tests.ps1](Tests/New-Spyder.Tests.ps1) |
| Strawberry Perl | [New-StrawberryPerl.ps1](Scripts/New-StrawberryPerl.ps1) | [New-StrawberryPerl.Tests.ps1](Tests/New-StrawberryPerl.Tests.ps1) |
| SuperPuTTY | [New-SuperPuTTY.ps1](Scripts/New-SuperPuTTY.ps1) | [New-SuperPuTTY.Tests.ps1](Tests/New-SuperPuTTY.Tests.ps1) |
| Thunderbird | [New-Thunderbird.ps1](Scripts/New-Thunderbird.ps1) | [New-Thunderbird.Tests.ps1](Tests/New-Thunderbird.Tests.ps1) |
| Thunderbird ESR | [New-ThunderbirdESR.ps1](Scripts/New-ThunderbirdESR.ps1) | [New-ThunderbirdESR.Tests.ps1](Tests/New-ThunderbirdESR.Tests.ps1) |
| TortoiseGit | [New-TortoiseGit.ps1](Scripts/New-TortoiseGit.ps1) | [New-TortoiseGit.Tests.ps1](Tests/New-TortoiseGit.Tests.ps1) |
| Total Commander | [New-TotalCommander.ps1](Scripts/New-TotalCommander.ps1) | [New-TotalCommander.Tests.ps1](Tests/New-TotalCommander.Tests.ps1) |
| uv | [New-AstralUv.ps1](Scripts/New-AstralUv.ps1) | [New-AstralUv.Tests.ps1](Tests/New-AstralUv.Tests.ps1) |
| Vim | [New-Vim.ps1](Scripts/New-Vim.ps1) | [New-Vim.Tests.ps1](Tests/New-Vim.Tests.ps1) |
| Visual Studio Code | [New-VsCode.ps1](Scripts/New-VsCode.ps1) | [New-VsCode.Tests.ps1](Tests/New-VsCode.Tests.ps1) |
| VLC Media Player | [New-VLC.ps1](Scripts/New-VLC.ps1) | [New-VLC.Tests.ps1](Tests/New-VLC.Tests.ps1) |
| WinMerge | [New-WinMerge.ps1](Scripts/New-WinMerge.ps1) | [New-WinMerge.Tests.ps1](Tests/New-WinMerge.Tests.ps1) |
| WinSCP | [New-WinSCP.ps1](Scripts/New-WinSCP.ps1) | [New-WinSCP.Tests.ps1](Tests/New-WinSCP.Tests.ps1) |
| Wireshark | [New-Wireshark.ps1](Scripts/New-Wireshark.ps1) | [New-Wireshark.Tests.ps1](Tests/New-Wireshark.Tests.ps1) |

Apps that are not covered yet, and why, are listed in [ToDo.md](ToDo.md).

### 🛠️ What did you build it with?
Scripts works in Powershell 5.1 and newer.