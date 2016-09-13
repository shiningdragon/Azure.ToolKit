<#
.SYNOPSIS
Copy a blob from one storage account to another, accounts can be in different regions and subscriptions

.DESCRIPTION
Copy a blob from one storage account to another, accounts can be in different regions and subscriptions

.EXAMPLE
Copy-BlobToStorageAccountSync -SourceBlobName 'blobName `
				-SourceStorageAccount 'sourceStorageAccount' `
				-SourceContainer 'sourceContainer' `
				-SourceSubscription 'sourceSubscription' `
				-DestBlobName 'destBlobName' `
				-DestStorageAccount 'destStorageAccountName' `
				-DestContainer 'destContainer' `
				-DestSubscription 'destContainer'
#>
function Copy-BlobToStorageAccountSync
{
	param
	(
		[Parameter(Mandatory=$true)][string]$SourceBlobName,
		[Parameter(Mandatory=$true)][string]$SourceStorageAccount,
		[Parameter(Mandatory=$true)][string]$SourceContainer,
		[Parameter(Mandatory=$true)][string]$SourceSubscription,
		$DestBlobName = $SourceBlobName,
		[Parameter(Mandatory=$true)][string]$DestStorageAccount,
		[Parameter(Mandatory=$true)][string]$DestContainer,
		[Parameter(Mandatory=$true)][string]$DestSubscription,
		[switch]$Force
	)

    $blobCopy = Copy-BlobToStorageAccountASync `
			-SourceBlobName  $SourceBlobName `
			-SourceStorageAccount $SourceStorageAccount `
			-SourceContainer $SourceContainer `
			-SourceSubscription $SourceSubscription `
			-DestBlobName $DestBlobName `
			-DestStorageAccount $DestStorageAccount `
			-DestContainer $DestContainer `
			-DestSubscription $DestSubscription `
			-Force:$Force

	while(($blobCopy | Get-AzureStorageBlobCopyState).Status -eq "Pending")
	{
		Start-Sleep -s 30
		$blobCopy | Get-AzureStorageBlobCopyState
	}
}

<#
.SYNOPSIS
Copy a blob from one storage account to another asynchronously

.DESCRIPTION
Copy a blob from one storage account to another, accounts can be in different regions and subscriptions. 
Returns an object that can be used to monitor the progress of the copy

.EXAMPLE
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

#>
function Copy-BlobToStorageAccountASync
{
	param
	(
		[Parameter(Mandatory=$true)][string]$SourceBlobName,
		[Parameter(Mandatory=$true)][string]$SourceStorageAccount,
		[Parameter(Mandatory=$true)][string]$SourceContainer,
		[Parameter(Mandatory=$true)][string]$SourceSubscription,
		$DestBlobName = $SourceBlobName,
		[Parameter(Mandatory=$true)][string]$DestStorageAccount,
		[Parameter(Mandatory=$true)][string]$DestContainer,
		[Parameter(Mandatory=$true)][string]$DestSubscription,
		[switch]$Force
	)

	# Source Storage Account Information 
	Select-AzureSubscription -subscriptionName $SourceSubscription | Out-Null
	$sourceStorageAccountKey = (Get-AzureStorageKey -StorageAccountName $SourceStorageAccount).Primary 
	$sourceContext = New-AzureStorageContext –StorageAccountName $SourceStorageAccount -StorageAccountKey $sourceStorageAccountKey  

	# Destination Storage Account Information 
	Select-AzureSubscription -subscriptionName $DestSubscription | Out-Null
	$destStorageAccountKey = (Get-AzureStorageKey -StorageAccountName $DestStorageAccount).Primary 	
	$destinationContext = New-AzureStorageContext –StorageAccountName $DestStorageAccount -StorageAccountKey $destStorageAccountKey 

	# Create the destination container if it doesn't already exist
	$existingContainer = Get-AzureStorageContainer -Name $DestContainer -Context $destinationContext -ErrorAction SilentlyContinue
	if($null -eq $existingContainer)
	{
		New-AzureStorageContainer -Name $DestContainer -Context $destinationContext -ErrorAction Stop
	}

	# Copy the blob 
	$blobCopy = $null
	if($force)
	{
		$blobCopy = Start-AzureStorageBlobCopy -DestBlob $DestBlobName `
								-DestContainer $DestContainer `
								-DestContext $destinationContext `
								-SrcBlob $SourceBlobName `
								-Context $sourceContext `
								-SrcContainer $SourceContainer `
								-Force `
								-ErrorAction Stop
	}
	else
	{
		$blobCopy = Start-AzureStorageBlobCopy -DestBlob $DestBlobName `
								-DestContainer $DestContainer `
								-DestContext $destinationContext `
								-SrcBlob $SourceBlobName `
								-Context $sourceContext `
								-SrcContainer $SourceContainer `
								-ErrorAction Stop
	}

	$blobCopy
}

Export-ModuleMember 'Copy-BlobToStorageAccountSync'
Export-ModuleMember 'Copy-BlobToStorageAccountASync'