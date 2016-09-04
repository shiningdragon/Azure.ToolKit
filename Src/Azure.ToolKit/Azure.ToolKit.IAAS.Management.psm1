Set-StrictMode -Version Latest

<#
.SYNOPSIS
Install the winrm cert for the azure vm onto the local machine

.DESCRIPTION
Install the winrim cert for the azure vm onto the local machine to enable powershell remoting from the local machine

.PARAMETER VMName
The name of the vm

.PARAMETER ServiceName
The name of the cloud service
#>
function Install-AzureVMWinRMCert
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)][string]$VMName,
		[Parameter(Mandatory = $true)][string]$ServiceName
	)
	
	Write-Output "Installing WinRM Certificate from VM: $VMName onto local machine"

	$VM = Get-AzureVM -name $vmName -ServiceName $serviceName -ErrorAction SilentlyContinue

	if($VM -eq $null)
	{
		throw "VM: $vmName does not exist in cloud service: $serviceName"
	}

	$winRMCert = ($VM| select -ExpandProperty vm).DefaultWinRMCertificateThumbprint
    
	if ($winRMCert -eq $Null)
	{
		throw "Default WinRM Certificate Thumbprint has no value"
	}
	else
	{
		Write-Output "Default WinRM Certificate: $winRMCert found on VM: $VMName"
	}

	$installedCert = Get-Item Cert:\LocalMachine\Root\$winRMCert -ErrorAction SilentlyContinue

	if ($installedCert -eq $null)
	{
		$certTempFile = [IO.Path]::GetTempFileName()
		$AzureX509cert = Get-AzureCertificate -ServiceName $($VM.serviceName) -Thumbprint $winRMCert -ThumbprintAlgorithm sha1
		$AzureX509cert.Data | Out-File $certTempFile
 
		# Target The Cert That Needs To Be Imported
		$CertToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certTempFile
 
		$store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
		$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
		$store.Add($CertToImport)
		$store.Close() 
		$removeresult=Remove-Item $certTempFile
		Write-Output  "WinRM Certificate installed onto local machine"
	}
	else
	{
		Write-Output  "WinRM Certificate already present on local machine"
	}
}

<#
.SYNOPSIS
Copy a file from your local machine to an azure vm

.DESCRIPTION
Copy a file from your local machine to an azure vm

.PARAMETER VMName
The name of the vm

.PARAMETER ServiceName
The name of the cloud service

.PARAMETER Credential
PSCredential with perms to connect remotely to the target vm

.PARAMETER LocalFile
The full path to the file to copy

.PARAMETER OverWrite
Overwrite the remote file if it already exists

.PARAMETER ChunkSizeMB
The chunk size (default 5 MB) used to stream the file across to the vm

.PARAMETER RemoteFile
The full path to the file on the azure vm

.EXAMPLE
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password

Copy-FileToAzureVM -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential -LocalFile "C:\myFile.txt" -RemoteFile  "C:\Documents\myFile.txt"
#>
function Copy-FileToAzureVM
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)][string]$VMName,
		[Parameter(Mandatory = $true)][string]$ServiceName,
		[Parameter(Mandatory)][PSCredential]$Credential,
	    [Parameter(Mandatory = $true)][string]$LocalFile,
		[Parameter(Mandatory = $true)][string]$RemoteFile,
		[boolean]$OverWrite = $true,
		[int]$ChunkSizeMB = 5
	)

	# The plan is is to open a remote connection to the vm and copy the file across through the remote connection in 1MB chunks
	# A powershell limitation limits this approach to 10 MB - hence we chunk it over in 1MB chunks
	Write-Output "Copy file $LocalFile to vm: $VMName"
	$session = $null
	$localFileStream = $null

	Install-AzureVMWinRMCert -VMName $VMName -ServiceName $ServiceName
	$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName
	$session = New-PSSession -ConnectionUri $winRmUri.ToString() -Credential $Credential	

	try 
	{
		# Open local file
		[IO.FileStream]$localFileStream = [IO.File]::OpenRead($LocalFile)

		# Open remote file on the server - handle remote errors
		Invoke-Command -Session $Session -ScriptBlock {
			Param
			(
				$RemoteFile, 
				$OverWrite
			)
			$remoteException = $null
			try 
			{
				if(-not $OverWrite)
				{
					if(Test-Path $RemoteFile)
					{
						throw "File $RemoteFile already exists on the remote machine, overwrite disabled"
					}
				}
				$dir = [IO.Path]::GetDirectoryName($RemoteFile)
				if (-not (Test-Path $dir))
				{
					Write-Host "Creating directory $dir"
					New-Item $dir -type directory -Force
				}
				[IO.FileStream]$remoteFileStream = [IO.File]::OpenWrite($RemoteFile)
			}
			catch 
			{
				$remoteException = $_
			}			
		} -ArgumentList $RemoteFile, $OverWrite
		$remoteException = Invoke-Command -Session $Session -ScriptBlock { $remoteException }
		if($remoteException -ne $null) 
		{
			throw $remoteException
		}

		# Copy file in chunks - handle remote errors
		$chunkSize = $ChunkSizeMB * 1024 * 1024
		[byte[]]$contentchunk = New-Object byte[] $chunkSize
		$bytesread = 0
		Write-Output "Starting file transfer"
		while (($bytesread = $localFileStream.Read( $contentchunk, 0, $chunkSize )) -ne 0)
		{
			$percent = $localFileStream.Position / $localFileStream.Length		
			Invoke-Command -Session $Session -ScriptBlock {
				Param($data, $bytes)
				$remoteException = $null
				try 
				{
					$remoteFileStream.Write( $data, 0, $bytes )
				}
				catch
				{
					$remoteException = $_
				}
			} -ArgumentList $contentchunk,$bytesread
			$remoteException = Invoke-Command -Session $Session -ScriptBlock { $remoteException }
			if($remoteException -ne $null)
			{
				throw "Error during file transfer: $remoteException"
			}
			Write-Output ("Sent {0} bytes: transfer {1:P2} complete, " -f $bytesread, $percent)
		}
		Write-Output "File transfer complete"
	}
	catch
	{
		throw $_
	}
	finally
	{
		if($localFileStream -ne $null) {
			$localFileStream.Close()
		}

		Invoke-Command -Session $Session -ScriptBlock {
			if($remoteFileStream -ne $null) {
				$remoteFileStream.Close()
			}
		}

		if($session -ne $null) {
			Remove-PSSession $session
		}
	}
}

<#
.SYNOPSIS
Execute the given script on the azure vm

.DESCRIPTION
Execute the given script on the azure vm

.PARAMETER VMName
The name of the vm

.PARAMETER ServiceName
The name of the cloud service

.PARAMETER Credential
PSCredential with perms to connect remotely to the target vm

.PARAMETER ScriptBlock
The powershell script to execute

.PARAMETER ArgumentList
An array of arguments to pass into the script block

.EXAMPLE
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
#>
function Invoke-RemoteScriptOnAzureVM
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)][string]$VMName,
		[Parameter(Mandatory = $true)][string]$ServiceName,
		[Parameter(Mandatory)][PSCredential]$Credential,
		[Parameter(Mandatory = $true)][ScriptBlock]$ScriptBlock,
		[array]$ArgumentList
	)

	Install-AzureVMWinRMCert -VMName $VMName -ServiceName $ServiceName
	$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName

	Write-Output "Executing script on vm: $VMName"
	$script = $ScriptBlock.ToString()
	Write-Output "Script: $script"

	Invoke-Command -ConnectionUri $winRmUri.ToString() -Credential $Credential -ScriptBlock $ScriptBlock `
		-ArgumentList $ArgumentList
}

<#
.SYNOPSIS
Install an msi on an azure vm

.DESCRIPTION
Install an msi on an azure vm. The msi is download onto the vm and then remotley executed

.PARAMETER VMName
The name of the vm

.PARAMETER ServiceName
The name of the cloud service

.PARAMETER Credential
PSCredential with perms to connect remotely to the target vm

.PARAMETER ProductName
The name of the product being installed

.PARAMETER MsiUrl
The url to download the msi from

.PARAMETER InstallDirectory
The local install directory on the target vm, defaults to 'C:\Installs'

.EXAMPLE
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password
$msiUrl = "http://download.octopusdeploy.com/octopus/Octopus.Tentacle.2.5.8.447-x64.msi"
Install-MsiToAzureVMFromUrl -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential -ProductName 'Octopus Tentacle' -MsiUrl $msiUrl -InstallDirectory 'C:/Installs'
#>
function Install-MsiToAzureVMFromUrl
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)][string]$VMName,
		[Parameter(Mandatory = $true)][string]$ServiceName,
		[Parameter(Mandatory)][PSCredential]$Credential,
		[Parameter(Mandatory = $true)][string]$ProductName,
	    [Parameter(Mandatory = $true)][string]$MsiUrl,
		[string]$InstallDirectory = 'C:\Installs'
	)

	Write-Output "Installing $MsiUrl onto $VMName"

	Install-AzureVMWinRMCert -VMName $VMName -ServiceName $ServiceName
	$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName
	$session = New-PSSession -ConnectionUri $winRmUri.ToString() -Credential $Credential			
	
	Write-Output "Install $ProductName onto vm: $VMName service: $serviceName"
	Invoke-Command -Session $session -ScriptBlock {
		param
		(
			$ProductName,
			$MsiUrl,
			$InstallDirectory
		)

		if (-not (Test-Path $InstallDirectory))
		{
			Write-Host "Creating directory $InstallDirectory"
			New-Item $InstallDirectory -type directory
		}
		$url = $MsiUrl
		$file = Join-Path $InstallDirectory "$ProductName.msi"
		$logFile = Join-Path $InstallDirectory "$ProductName.log"
		if (Test-Path $file)
		{
			Write-Host "Deleting exisiting file: $file"
			Remove-Item $file
		}
		Write-Host "Download msi: $url to $file"
		$webclient = New-Object System.Net.WebClient
		$webclient.DownloadFile($url,$file)

		Write-Host "Running msi: $file"
		& cmd /c msiexec /i $file /L*v $logFile /quiet 
	} -ArgumentList $ProductName, $MsiUrl, $InstallDirectory

	$exitCode = Invoke-Command -session $session -ScriptBlock {$LASTEXITCODE}

	Remove-PSSession $session

	if($exitCode -eq 0)
	{
		Write-Output "Product $ProductName successfully installed"
	}
	else
	{
		Write-Error "Product $ProductName was not successfully installed, exited with error code: $exitCode. See install log at $InstallDirectory on target vm"
	}
}

<#
.SYNOPSIS
Install an msi on an azure vm

.DESCRIPTION
Install an msi on an azure vm. The msi is copied onto the vm from a local file location and then remotley executed

.PARAMETER VMName
The name of the vm

.PARAMETER ServiceName
The name of the cloud service

.PARAMETER Credential
PSCredential with perms to connect remotely to the target vm

.PARAMETER ProductName
The name of the product being installed

.PARAMETER LocalFile
The local path to the msi

.PARAMETER InstallDirectory
The local install directory on the target vm, defaults to 'C:\Installs'

.EXAMPLE
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password
Install-MsiToAzureVMFromFile -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential -ProductName 'Azure Powershell' -LocalFile 'C:/azure-powershell.2.0.1.msi' -InstallDirectory 'C:/Installs'
#>
function Install-MsiToAzureVMFromFile
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)][string]$VMName,
		[Parameter(Mandatory = $true)][string]$ServiceName,
		[Parameter(Mandatory)][PSCredential]$Credential,
		[Parameter(Mandatory = $true)][string]$ProductName,
	    [Parameter(Mandatory = $true)][string]$LocalFile,
		[string]$InstallDirectory = 'C:\Installs'
	)

	Write-Output "Installing $LocalFile onto $VMName"

	# First copy the file to the VM
	$remoteFile = Join-Path $InstallDirectory "$ProductName.msi"
	$remoteLogFile = Join-Path $InstallDirectory "$ProductName.log"
	Copy-FileToAzureVM -VMName $VMName -ServiceName $ServiceName -Credential $Credential -LocalFile $LocalFile -RemoteFile $remoteFile

	# Remotley Install it
	$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName
	$session = New-PSSession -ConnectionUri $winRmUri.ToString() -Credential $Credential			
	
	Write-Output "Install $ProductName onto vm: $VMName service: $serviceName"
	Invoke-Command -Session $session -ScriptBlock {
		param
		(
			$ProductName,
			$remoteFile,
			$remoteLogFile
		)

		Write-Host "Running msi: $remoteFile"
		& cmd /c msiexec /i $remoteFile /L*v $remoteLogFile /quiet 
	} -ArgumentList $ProductName, $remoteFile, $remoteLogFile

	$exitCode = Invoke-Command -session $session -ScriptBlock {$LASTEXITCODE}

	Remove-PSSession $session

	if($exitCode -eq 0)
	{
		Write-Output "Product $ProductName successfully installed"
	}
	else
	{
		Write-Error "Product $ProductName was not successfully installed, exited with error code: $exitCode. See install log at $InstallDirectory on target vm"
	}
}

<#
.SYNOPSIS
Return the .NET version installed on an azure vm

.DESCRIPTION
Return the .NET version installed on an azure vm

.PARAMETER VMName
The name of the vm

.PARAMETER ServiceName
The name of the cloud service

.PARAMETER Credential
PSCredential with perms to connect remotely to the target vm

.EXAMPLE
$password = ConvertTo-SecureString -String "password" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'username', $password
Get-AzureVMDotNetVersion -VMName 'myVM' -ServiceName 'myCloudService' -Credential $credential
#>
function Get-AzureVMDotNetVersion
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)][string]$VMName,
		[Parameter(Mandatory = $true)][string]$ServiceName,
		[Parameter(Mandatory)][PSCredential]$Credential
	)

	# See https://msdn.microsoft.com/library/hh925568(v=vs.110).aspx
	$scriptBlock = {
		$prop = Get-ItemProperty -Path "hklm:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\" -ErrorAction SilentlyContinue
		if($prop -ne $null)
		{
			$release = $prop.Release
			switch ($release)
			{
				"378389" { $version = ".NET 4.5" }
				"378675" { $version = ".NET 4.5.1" }
				"378758" { $version = ".NET 4.5.1" }
				"379893" { $version = ".NET 4.5.2" }
				"393297" { $version = ".NET 4.6" }
				"393295" { $version = ".NET 4.6" }
				"394254" { $version = ".NET 4.6.1" }
				"394271" { $version = ".NET 4.6.1" }
				"394802" { $version = ".NET 4.6.2" }
				"394806" { $version = ".NET 4.6.2" }
				default  { $version = "Unknown .NET version" }
			}
		}
		else
		{
			$version =  "Unable to determine of .NET Framework version"
		}
	}

	Install-AzureVMWinRMCert -VMName $VMName -ServiceName $ServiceName > Out-Null
	$winRmUri = Get-AzureWinRMUri -ServiceName $ServiceName -Name $VMName 
	$session = New-PSSession -ConnectionUri $winRmUri.ToString() -Credential $Credential
	
	Invoke-Command -Session $session -ScriptBlock $scriptBlock

	$version = Invoke-Command -Session $session -ScriptBlock {$version}

	Remove-PSSession $session

	$result = New-Object –TypeName PSObject –Prop (@{'Name'=$VMName; 'ServiceName' = $ServiceName; 'DotNET_Version' = $version})
	$result
}

#Export-ModuleMember 'Install-AzureVMWinRMCert'
Export-ModuleMember 'Copy-FileToAzureVM'
Export-ModuleMember 'Invoke-RemoteScriptOnAzureVM'
Export-ModuleMember 'Install-MsiToAzureVMFromUrl'
Export-ModuleMember 'Install-MsiToAzureVMFromFile'
Export-ModuleMember 'Get-AzureVMDotNetVersion'






