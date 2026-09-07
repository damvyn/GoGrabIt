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
> [!NOTE]
> Make sure the execution policy is RemoteSign or less strict
> You may need to unblock New-Something.ps1 in Properties.

### 🛠️ What did you build it with?
Scripts works in Powershell 5.1 and newer.