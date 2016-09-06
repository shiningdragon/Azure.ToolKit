$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\..\Azure.ToolKit" -Force

#############################################################
# Must manually update this data befiore performing this test
#############################################################
$sourceSubscription = 'Visual Studio Ultimate with MSDN'
$sourceVMName = 'tdc2sdtest01'
$sourceServiceName = 'tdc2sdtest'

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
		}
    }
}