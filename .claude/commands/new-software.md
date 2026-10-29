---
description: Create a new script in Scripts folder
argument-hint: ProductName | Vendor | Download Url | CommandLine (omit CommandLine for msix/appx packages)
---

## Context parse $Arguments to get the following values:
    - [ProductName]: name of the software that is used for file name e.g New-[Productname].ps1
    - [Vendor]: name of the vendor that is used for generating folder structure
    - [Download Url]: a source url to parse and get version and direct download url
    - [CommandLine]: command for silent install (exe/msi only; not used for msix/appx packages)

## Task
- Make a new script @Scripts\New-[Productname].ps1
- use @templates\new-software.ps1 as a regerence to make the script
    - "# get product version and validate" section contains an example how to extract version
    - "# get direct download Url and validate"  section contains an example how to extract direct download
- choose the install template by the type of the package the source provides:
    - exe, msi (also inside a zip): use @templates\installtemplate.ps1 as a value for installTemplate varible
    - msix, msixbundle, appx, appxbundle (also inside a zip): use @templates\installtemplate-appx.ps1 as a value for installTemplate varible, see "Appx/MSIX packages" below

## Appx/MSIX packages
The appx template provisions the package for all users with Add-AppxProvisionedPackage.
- Product information block has no $installParams and no $exitCodes. Use these variables instead:
    - $searchPattern: regex for the main package (or for the zip that contains it)
    - $dependencyDir: subfolder for dependency packages (e.g. 'Dependencies'), '' if the product has none
    - $dependencyFilter: filter for dependencies to install (e.g. '*x64*'), '' if none
    - $dependencyPattern: regex for a separate dependencies asset (e.g. a Dependencies.zip), only if the source publishes it
- Product name and version come only from the source site (e.g. tag_name). Never open the package and read name/version from its manifest in the New-[Productname].ps1 script.
- Download the main package. If it is a zip, Expand-Archive it into $installerDir, delete the zip, then find the main package (.msixbundle, .msix) and set $fileName to its name. Exit 1 if no package was found.
- Dependencies: move loose *.appx files into $installerDir\$dependencyDir, or download and expand the separate dependencies asset into that folder.
- Replace placeholders in the template: <APPNAME>, <VERSION>, <FILE>, <DEPDIR>, <DEPFILTER>. Use '' for the dependency placeholders when they do not apply.
- Install.ps1 may read the manifest of a package; this is only to compare with packages already on the system. It is not a source for names or versions of the generated folder or messages.


## Testing
- Make a Petster test script @Tests\New-[Productname].Tests.ps1 to test basic use cases
- use @Tests\New-7Zip.Tests.ps1 as a reference to make the test file for the new script
- for a package inside a zip use @Tests\New-Paint.Net.Tests.ps1 as a reference (mock Expand-Archive)
- for appx/msix also assert: main package and dependency files exist, Install.ps1 contains the package file name, the dependency folder and filter, and no unreplaced placeholders remain
- add the new script to the table in ReadMe.md
