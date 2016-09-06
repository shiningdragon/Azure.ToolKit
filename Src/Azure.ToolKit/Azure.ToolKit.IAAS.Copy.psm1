<#
.SYNOPSIS
Copy a VM. It is possible to move vms across regions, subscriptions and vnets using this command

.DESCRIPTION
Copy a VM. It is possible to move vms across regions, subscriptions and vnets using this command
VM must be stopped before running this script and any static ip on the source vm must be removed i.e. it must be set to a dynamic ip

.PARAM SourceSubscription
The source subscription

.PARAM SourceServiceName
The source cloud service

.PARAM SourceVMName
The source vm name

.PARAM DestSubscription
The destination subscription

.PARAM DestServiceName
The destination cloud service

.PARAM DestVMName
The destination vm name

.PARAM DestLocation
The dedstination Azure region

.PARAM DestStorageAccount
Destintaion storage account. Copys of the vm disks will be made in this account

.PARAM DestContainer
Destination container - created if not already present

.PARAM DestVnetName
The destination vnet. If blank the dest vm will not be placed in a vnet

.PARAM DestSubnetName
The destination subnet, must be specified if destvnet is specified

.PARAM PerformVhdBlobCopy
You can use $PerformVhdBlobCopy to control if the vhd copy is performed - e.g. if you previously copied the vhds successfully but the vm creation failed for another reason

.PARAM OverwriteDestDisks
You can use $OverwriteDestDisks to control whether you create the dest disks - e.g. if you previously suceedded in creating the dest disks but the vm creation failed for another reason

.EXAMPLE
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
#>
function Copy-AzureVM
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)][string]$SourceSubscription,
		[Parameter(Mandatory=$true)][string]$SourceServiceName,
		[Parameter(Mandatory=$true)][string]$SourceVMName,

		[Parameter(Mandatory=$true)][string]$DestSubscription,
		[Parameter(Mandatory=$true)][string]$DestServiceName,
		[Parameter(Mandatory=$true)][string]$DestVMName,
		[Parameter(Mandatory=$true)][string]$DestLocation,
		[Parameter(Mandatory=$true)][string]$DestStorageAccount,
		[Parameter(Mandatory=$true)][string]$DestContainer,
		[string]$DestVnetName,
		[string]$DestSubnetName,		

		[boolean]$PerformVhdBlobCopy = $true,
		[boolean]$OverwriteDestDisks = $true
	)

	# This is a 3 stage operation
	# 1) copy the vhds to a new storage account
	# 2) create new disks from the copied vhds
	# 3) create the vm from these new disks
	
	# Pre conditions
	if(![string]::IsNullOrEmpty($DestVMName) -and [string]::IsNullOrEmpty($DestSubnetName))
	{
		throw "You must set the dest subnet name if you set the dest vm name"
	}
	$sourceVM = Get-AzureVM -ServiceName $SourceServiceName -Name $SourceVMName
	$staticIP = Get-AzureStaticVNetIP -VM $sourceVM
	if($null -ne $staticIP)
	{
		throw "Can not copy a vm with a static ip. Please set the source vm to a dynamic ip"
	}

	# Export the source vm config
	Select-AzureSubscription -SubscriptionName $SourceSubscription 
	$tempPath = [System.IO.Path]::GetTempPath()
	$exportPath = "{0}\{1}-{2}-State.xml" -f $tempPath, $SourceServiceName, $SourceVMName 
	Write-Output "Exporting the vm config to $exportPath"
	Export-AzureVM -ServiceName $SourceServiceName -Name $SourceVMName -Path $exportPath
		
	$disks = Get-AzureDisk | ? { 
		![string]::IsNullOrEmpty($_.AttachedTo) -and $_.AttachedTo.RoleName -eq $SourceVMName 
	}

	# Copy the disks
	if($PerformVhdBlobCopy)
	{
		# vm must be stopped before we move its disks
		
		if($sourceVM.InstanceStatus -ne "StoppedDeallocated")
		{
			Write-Output "Stopping vm $SourceVMName"
			Stop-AzureVM -ServiceName $SourceServiceName -Name $SourceVMName
		}

		$copyTasks = @()
		foreach($disk in $disks)
		{
			$srcContainer = ($disk.MediaLink.Segments[1]).Replace("/","")
			$blobName = $disk.MediaLink.Segments | Where-Object { $_ -like "*.vhd" } 
			$destBlobName = "$DestServiceName-$DestVMName-$blobName"
			$srcStorageAccount = $disk.MediaLink.Host.Replace(".blob.core.windows.net", "")
			Write-Output "Copying disk $blobName from $srcStorageAccount to $DestStorageAccount"
			$copyTask = Copy-BlobToStorageAccountASync `
				-SourceBlobName  $blobName `
				-SourceStorageAccount $srcStorageAccount `
				-SourceContainer $srcContainer `
				-SourceSubscription $SourceSubscription `
				-DestBlobName $destBlobName `
				-DestStorageAccount $DestStorageAccount `
				-DestContainer $DestContainer `
				-DestSubscription $DestSubscription `
				-Force

			$copyTasks += $copyTask
		}

		# Wait for all copy tasks to end
		$complete = $false
		while(!$complete)
		{
			$complete =  $true
			$copyTasks | % {
				$_ | Get-AzureStorageBlobCopyState
				if(($_ | Get-AzureStorageBlobCopyState).Status -eq "Pending")
				{
					$complete =  $false
				}
			}	
			Start-Sleep -s 60
		}
	}

	# Set destination subscription context
	Select-AzureSubscription -SubscriptionName $DestSubscription
	Set-AzureSubscription -SubscriptionName $DestSubscription -CurrentStorageAccountName $DestStorageAccount

	# Create the dest cloud service if it doesnt already exists
	$service = Get-AzureService -ServiceName $DestServiceName -ErrorAction SilentlyContinue       
	if ($null -eq $service) 
    {
		Write-Output "Creating Azure cloud service: $DestServiceName in region: $DestLocation"
		New-AzureService -ServiceName $DestServiceName -Location $DestLocation -ErrorAction Stop
	}

	# Load VM config
	$vmConfig = Import-AzureVM -Path $exportPath
 
	# Loop through each disk again and create the destination disks
	$diskNum = 0
	foreach($disk in $disks)
	{
		# Construct new Azure disk name as [DestServiceName]-[DestVMName]-[Index]
		$destDiskName = "{0}-{1}-{2}" -f $DestServiceName, $DestVMName, $diskNum  
 
		# Check if an Azure Disk already exists in the destination subscription
		$azureDisk = Get-AzureDisk -DiskName $destDiskName `
								  -ErrorAction SilentlyContinue `
								  -ErrorVariable LastError

		if ($azureDisk -ne $null)
		{
			Write-Output "Disk: $destDiskName already exists"

			if ($OverwriteDestDisks -eq $true)
			{
				Write-Output "Deleting disk: $destDiskName"
				Remove-AzureDisk -DiskName $destDiskName            
				$azureDisk = $null
			}
		}
 
		# Determine media location
		$blobName = $disk.MediaLink.Segments | Where-Object { $_ -like "*.vhd" }
		$destBlobName = "$DestServiceName-$DestVMName-$blobName"
		$destMediaLocation = "http://{0}.blob.core.windows.net/{1}/{2}" -f $DestStorageAccount,$DestContainer,$destBlobName
 
		# Attempt to add the azure OS or data disk
		if ($disk.OS -ne $null -and $disk.OS.Length -ne 0)
		{
			if ($azureDisk -eq $null)
			{
				Write-Output "Creating OS disk $destDiskName from vhd $destMediaLocation"
				$azureDisk = Add-AzureDisk -DiskName $destDiskName `
											-MediaLocation $destMediaLocation `
											-Label $destDiskName `
											-OS $disk.OS `
											-ErrorAction SilentlyContinue `
											-ErrorVariable LastError
			}
        
 
			# Update VM config
			$vmConfig.OSVirtualHardDisk.DiskName = $azureDisk.DiskName
		}
		else
		{
			# Data disk
			if ($azureDisk -eq $null)
			{
				Write-Output "Creating data disk $destDiskName from vhd $destMediaLocation"
				$azureDisk = Add-AzureDisk -DiskName $destDiskName `
											-MediaLocation $destMediaLocation `
											-Label $destDiskName `
											-ErrorAction SilentlyContinue `
											-ErrorVariable LastError
			}
         
			# Update VM config
			# Match on source disk name and update with dest disk name
			$vmConfig.DataVirtualHardDisks | % { 
				if($_.DiskName -eq $disk.DiskName)
				{
					$_.DiskName = $azureDisk.DiskName
				}             
			}
		}              
 
		# Next disk number
		$diskNum = $diskNum + 1
	}

	# Create destination VM
	$vmConfig.RoleName = $DestVMName

	if([string]::IsNullOrEmpty($DestSubnetName))
	{
		$vmConfig.ConfigurationSets[0].SubNetNames = $null
	}
	else
	{
		$vmConfig | Set-AzureSubnet $DestSubnetName
	}

	Write-Output "Creating new VM $DestVMName in cloud service $DestServiceName"

	if([string]::IsNullOrEmpty($DestVnetName))
	{
		$vmConfig | New-AzureVM -ServiceName $DestServiceName -WaitForBoot
	}
	else
	{
		$vmConfig | New-AzureVM -ServiceName $DestServiceName -VNetName $DestVnetName -WaitForBoot
	}
}

Export-ModuleMember 'Copy-AzureVM'