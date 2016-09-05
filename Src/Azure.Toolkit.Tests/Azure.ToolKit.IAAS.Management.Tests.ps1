$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\..\Azure.ToolKit" -Force

###########################################################################
# In a perfect world, every time the tests run we would automatically delete and 
# recreate this vm in azure to ensure test start conditions are always constant.
# This takes times so it will be left as amanual task so the same vm and be reused if needed
############################################################################
$location = "West Europe"
$vmName = "myVM"
$serviceName = "myService"
$username = "user"
$password = "password"
$pword = ConvertTo-SecureString -String $password -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $pword
#############################################################################

Describe "Invoke-RemoteScriptOnAzureVM" {

	Context "Executes script on vm" {
		It "Executes script on vm" {	

			$scriptBlock = {
				param
				(
					$fileName
				)
				New-Item $fileName -type file
			}

			$now = [DateTime]::Now.Millisecond
			$name = "testfile_" + $now + ".txt"
			$fileName = join-path 'c:/unittestdata' $name
			Invoke-RemoteScriptOnAzureVM -VMName $vmName -ServiceName $serviceName -Credential $credential `
				-ScriptBlock $scriptBlock -ArgumentList @($fileName)

			# Verify script ran correctly, file must exist
			$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName 
			$session = New-PSSession -ConnectionUri $winRmUri.ToString() -Credential $credential
			Invoke-Command -Session $session -ScriptBlock {
				param($fileName)
				$exists = $false
				$exists = Test-Path $fileName
			} -ArgumentList $fileName
			$exists = Invoke-Command -Session $session -ScriptBlock {$exists}
			Remove-PSSession $session
			$exists | Should Be True
		}
    }
}

Describe "Install-MsiToAzureVMFromFile" {

	Context "Installs azure powershell to the vm" {
		It "Installs azure powershell to the vm" {	

			$msiUrl = "https://github.com/Azure/azure-powershell/releases/download/v1.7.0-August2016/azure-powershell.1.7.0.msi"
			$tempPath = [IO.Path]::GetTempPath()
			$msiLocalFile = join-path $tempPath 'azure-powershell.1.7.0.msi' 
			# Download msi to computer
			$webclient = New-Object System.Net.WebClient
			$webclient.DownloadFile($msiUrl,$msiLocalFile)

			Install-MsiToAzureVMFromFile -VMName $vmName -ServiceName $serviceName -Credential $credential -ProductName 'azure-powershell.1.7.0' `
				-LocalFile $msiLocalFile -InstallDirectory 'C:\UnitTestInstalls'

			# Verify it installed correctly
			$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName 
			$session = New-PSSession -ConnectionUri $winRmUri.ToString() -Credential $credential
			Invoke-Command -Session $session -ScriptBlock {
				Import-Module Azure
				$azurePSVersion = (Get-Module Azure).Version
			} 
			$azurePSVersion = Invoke-Command -Session $session -ScriptBlock {$azurePSVersion}
			Remove-PSSession $session
			$azurePSVersion | Should Be '1.6.1'
		}
    }
}

Describe "Install-MsiToAzureVMFromUrl" {

	Context "Install octopus tentacle to the vm" {
		It "Install octopus tentacle to the vm" {	

			$octoTentacleUrl = "http://download.octopusdeploy.com/octopus/Octopus.Tentacle.2.5.8.447-x64.msi"
			Install-MsiToAzureVMFromUrl -VMName $vmName -ServiceName $serviceName -Credential $credential -ProductName 'octoprodname' `
			-MsiUrl $octoTentacleUrl -InstallDirectory 'C:\UnitTestInstalls'

			# Verify it installed correctly
			$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName 
			$session = New-PSSession -ConnectionUri $winRmUri.ToString() -Credential $credential
			Invoke-Command -Session $session -ScriptBlock {
				$object = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | `
				Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | ? `
				{$_.DisplayName -eq 'Octopus Deploy Tentacle' -and $_.DisplayVersion -eq '2.5.8.447'}
			} 
			$object = Invoke-Command -Session $session -ScriptBlock {$object}
			Remove-PSSession $session
			$object | Should Not Be Null
		}
    }
}

Describe "Get-AzureVMDotNetVersion" {

	Context "Get the .NET Version of an Azure VM" {
		It "Should return 4.6.1" {	
			$version = Get-AzureVMDotNetVersion -VMName $vmName -ServiceName $serviceName -Credential $credential
			$version.DotNET_Version | Should Be ".NET 4.6.1"
		}
    }
}

Describe "Copy-FileToAzureVM" {

	Context "Copy a local file to an Azure VM" {
		It "Should copy given local file to the azure vm" {	
			$localFile = [IO.Path]::GetTempFileName()
			$now = (Get-Date).ToString() 
			$now > $localFile
			Copy-FileToAzureVM -VMName $vmName -ServiceName $serviceName -Credential $credential `
				-LocalFile $localFile -RemoteFile  "C:\unittestdata\test.txt" -ChunkSizeMB 1

			# Verify it copied correctly
			$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName 
			$session = New-PSSession -ConnectionUri $winRmUri.ToString() -Credential $credential
			Invoke-Command -Session $session -ScriptBlock {
				$data = Get-Content "C:\unittestdata\test.txt" -Raw
			} 
			$testdata = Invoke-Command -Session $session -ScriptBlock {$data}
			Remove-PSSession $session
			$testdata.Trim() | Should Be $now

			{Copy-FileToAzureVM -VMName $vmName -ServiceName $serviceName -Credential $credential `
				-LocalFile $localFile -RemoteFile  "C:\unittestdata\test.txt" -OverWrite $false } | Should Throw
		}
    }
}