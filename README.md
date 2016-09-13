# Azure.ToolKit

Azure.Toolkit is a powershell module providing advanced commands to manage classic Azure virtual machines

*New functionality is currently being added and support for Azure RM virtual machines will come soon.*

## Latest Release ##

Install it direct from the powershell gallery
https://www.powershellgallery.com/packages/Azure.ToolKit/

## Notes ##
All comands that connect remotley to the Azure vm do so over the public powershell endpoint. As such, the target vm requires an open powershell endpoint on port 5986. Support for connection through site to site vpn to come soon.

### Copy-AzureVM ###
Copy a classic VM. It is possible to move vms across regions, subscriptions and vnets using this command

```
# Copy vm to a new vnet in a different region and subscription

Copy-AzureVM -SourceSubscription 'sourceSubscription' `
	-SourceServiceName 'sourceServiceName' `
	-SourceVMName 'sourceVMNam' `
	-DestSubscription 'destSubscription' `
	-DestServiceName 'destServiceName' `
	-DestVMName 'destVMName' `
	-DestLocation 'North Europe' `
	-DestStorageAccount 'NorthEuropeStorage' `
	-DestContainer 'vhds' `
	-DestVnetName 'NorthEuropeVNet' `
	-DestSubnetName 'Subnet-1' `
	-PerformVhdBlobCopy $true `
	-OverwriteDestDisks $true 
```

### Copy-FileToAzureVM ###
Copy a file from your local machine to an Azure vm

```
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password

Copy-FileToAzureVM -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential -LocalFile "C:\myFile.txt" -RemoteFile  "C:\Documents\myFile.txt"
```

### Invoke-RemoteScriptOnAzureVM ###
Execute the given script on the Azure vm

```
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password

$ScriptBlock = {
	Param
	(
		[int]$diskNumber = 0
	)
	(Get-Disk -Number $diskNumber).FriendlyName
}
$ArgumentList = @(0)

Invoke-RemoteScriptOnAzureVM -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
```

### Install-MsiToAzureVMFromUrl ###
Install an msi on an Azure vm. The msi is download onto the vm and then remotley executed

```
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password
$msiUrl = "http://download.octopusdeploy.com/octopus/Octopus.Tentacle.2.5.8.447-x64.msi"

Install-MsiToAzureVMFromUrl -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential -ProductName 'Octopus Tentacle' -MsiUrl $msiUrl 
```

### Install-MsiToAzureVMFromFile ###
Install an msi on an Azure vm. The msi is copied onto the vm from a local file location and then remotley executed

```
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password

Install-MsiToAzureVMFromFile -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential -ProductName 'Azure Powershell' -LocalFile 'C:/azure-powershell.2.0.1.msi' 
```

### Get-AzureVMDotNetVersion ###
Return the .NET version installed on an Azure vm

```
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password

Get-AzureVMDotNetVersion -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential
```

### Set-WindowsUpdateOnAzureVM ###
Sets the win update settings on the target vm

```
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password

Set-WindowsUpdateOnAzureVM -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential -Setting "NoCheck"
```

### Copy-BlobToStorageAccountSync ###
Synchronously copy a blob from one storage account to another. Works across regions and subscriptions

```
Copy-BlobToStorageAccountSync -SourceBlobName 'blobName `
				-SourceStorageAccount 'sourceStorageAccount' `
				-SourceContainer 'sourceContainer' `
				-SourceSubscription 'sourceSubscription' `
				-DestBlobName 'destBlobName' `
				-DestStorageAccount 'destStorageAccountName' `
				-DestContainer 'destContainer' `
				-DestSubscription 'destContainer'
```

### Copy-BlobToStorageAccountASync ###
Asynchronously copy a blob from one storage account to another. Works across regions and subscriptions
Returns an object that can be used to monitor the progress of the copy

```
$copyTask = Copy-BlobToStorageAccountASync -SourceBlobName 'blobName `
				-SourceStorageAccount 'sourceStorageAccount' `
				-SourceContainer 'sourceContainer' `
				-SourceSubscription 'sourceSubscription' `
				-DestBlobName 'destBlobName' `
				-DestStorageAccount 'destStorageAccountName' `
				-DestContainer 'destContainer' `
				-DestSubscription 'destContainer'

if(($copyTask | Get-AzureStorageBlobCopyState).Status -eq "Success")
{
	# Copy complete
}
```