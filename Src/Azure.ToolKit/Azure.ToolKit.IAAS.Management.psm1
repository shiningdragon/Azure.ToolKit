Set-StrictMode -Version Latest

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

.PARAMETER RemoteFile
The full path to the file on the azure vm
#>
function Copy-FileToAzureVM
{
	param(
		[Parameter(Mandatory = $true)][string]$VMName,
		[Parameter(Mandatory = $true)][string]$ServiceName,
		[Parameter(Mandatory)][PSCredential]$Credential,
	    [Parameter(Mandatory = $true)][string]$LocalFile,
		[Parameter(Mandatory = $true)][string]$RemoteFile
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
			Param($RemoteFile)
			$remoteException = $null
			try 
			{
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
		} -ArgumentList $RemoteFile
		$remoteException = Invoke-Command -Session $Session -ScriptBlock { $remoteException }
		if($remoteException -ne $null) 
		{
			throw "Error opening remote file stream: $remoteException"
		}

		# Copy file in chunks - handle remote errors
		$chunksize = 5MB
		[byte[]]$contentchunk = New-Object byte[] $chunksize
		$bytesread = 0
		Write-Output "Starting file transfer"
		while (($bytesread = $localFileStream.Read( $contentchunk, 0, $chunksize )) -ne 0)
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
array of arguments to pass into the script block
#>
function Invoke-RemoteScriptOnAzureVM
{
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
Install the winrim cert for the azure vm onto the local machine

.DESCRIPTION
Install the winrim cert for the azure vm onto the local machine to enable powershell remoting from the local machine

.PARAMETER VMName
The name of the vm

.PARAMETER ServiceName
The name of the cloud service
#>
function Install-AzureVMWinRMCert
{
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

Export-ModuleMember 'Copy-FileToAzureVM'
Export-ModuleMember 'Install-AzureVMWinRMCert'
Export-ModuleMember 'Invoke-RemoteScriptOnAzureVM'






