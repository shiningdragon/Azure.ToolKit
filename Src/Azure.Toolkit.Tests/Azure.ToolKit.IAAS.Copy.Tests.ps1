$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Remove-Module 'Azure.Toolkit' # remove any previously loaded version
Import-Module "$here\..\Azure.ToolKit" -Force
(Get-Module 'azure.toolkit').path

# Pre conditions
$image = Get-AzureVMImage | Where-Object {$_.imagefamily -eq 'Windows Server 2012 R2 Datacenter' } | sort-object Publisheddate -Descending | select-object -first 1
$imageName = $image.ImageName
$sourceSubscription = 'Visual Studio Ultimate with MSDN'
$sourceVMName = 'tdc2sdtest01'
$sourceServiceName = 'tdc2sdtest'
$sourceLocation = 'North Europe'
$username = 'pvmadmin'
$password = ''

$destSubscription = 'Visual Studio Ultimate with MSDN'
$destVMName = $sourceVMName + "copy"
$destServiceName = $sourceServiceName + "copy"
$destStorageAccount = 'sdstoreuwtest01'
$destLocation = 'West Europe'
$destVnet = 'sdvnet-euw'
$destSubnet = 'Subnet-1'


Describe "Copy-AzureVM" {

	Context "Copy a VM" {
		It "Copy a VM" {	

			# ensure dest vm is not present
			$vm = Get-AzureVM -ServiceName $destServiceName -Name $destVMName -ErrorAction SilentlyContinue
			if($null -ne $vm)
			{
				Remove-AzureVM -ServiceName $destServiceName -Name $destVMName -DeleteVHD 
				Start-Sleep -Seconds 120
			}

			# ensure source vm is present
			$vm = $null
			$vm = Get-AzureVM -ServiceName $sourceServiceName -Name $sourceVMName -ErrorAction SilentlyContinue
			if($null -eq $vm)
			{				
				New-AzureQuickVM –Windows –ServiceName $sourceServiceName –name $sourceVMName –ImageName $imageName –Password $password -AdminUsername $username -Location $sourceLocation -WaitForBoot
			}

			Copy-AzureVM `
				-SourceSubscription $sourceSubscription `
				-SourceServiceName $sourceServiceName `
				-SourceVMName $sourceVMName `
				-DestSubscription $destSubscription `
				-DestServiceName $destServiceName `
				-DestVMName $destVMName `
				-DestLocation $destLocation `
				-DestStorageAccount $destStorageAccount `
				-DestContainer 'vhds' `
				-DestVnetName $destVnet `
				-DestSubnetName  $destSubnet `
				-PerformVhdBlobCopy $true `
				-OverwriteDestDisks $true 

			$vm = Get-AzureVM -ServiceName $destServiceName -Name $destVMName
			$vm | Should Not Be Null

			$vm.VirtualNetworkName | Should Be $destVnet
			Get-AzureSubnet -VM $vm | Should Be $destSubnet

			# Clean up
			Remove-AzureVM -ServiceName $destServiceName -Name $destVMName -DeleteVHD 
			Remove-AzureService -ServiceName $destServiceName 
		}
    }
}