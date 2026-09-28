---
description: Create a new script in Scripts folder
argument-hint: ProductName | Vendor | Download Url | CommandLine
---

## Context parse $Arguments to get the following values:
    - [ProductName]: name of the software that is used for file name e.g New-[Productname].ps1
    - [Vendor]: name of the vendor that is used for generating folder structure
    - [Download Url]: a source url to parse and get version and direct download url
    - [CommandLine]: command for silent install

## Task
- Make a new script @Scripts\New-[Productname].ps1
- use @templates\new-software.ps1 as a regerence to make the script
    - "# get product version and validate" section contains an example how to extract version
    - "# get direct download Url and validate"  section contains an example how to extract direct download
- use @templates\installtemplate.ps1 as a value for installTemplate varible


## Testing
- Make a Petster test script @Tests\New-[Productname].Tests.ps1 to test basic use cases
- use @Tests\New-7Zip.Tests.ps1 as a reference to make the test file for the new script