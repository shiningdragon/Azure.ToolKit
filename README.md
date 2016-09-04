# Azure.ToolKit

Azure.Toolkit is a powershell module providing advanced commands to manage classic Azure virtual machines

*This module is a work in progress. New functionality is currently being added and support for Azure RM virtual machines will come soon.*

### Notes ###
All comands that connect remotley to the Azure vm do so over the public powershell endpoint. As such, the target vm requires an open powershell endpoint on port 5986. Support for connection through site to site vpn to come soon.

### Copy-FileToAzureVM ###
Copy a file from your local machine to an Azure vm

### Invoke-RemoteScriptOnAzureVM ###
Execute the given script on the Azure vm

### Install-MsiToAzureVMFromUrl ###
Install an msi on an Azure vm. The msi is download onto the vm and then remotley executed

### Install-MsiToAzureVMFromFile ###
Install an msi on an Azure vm. The msi is copied onto the vm from a local file location and then remotley executed

### Get-AzureVMDotNetVersion ###
Return the .NET version installed on an Azure vm
