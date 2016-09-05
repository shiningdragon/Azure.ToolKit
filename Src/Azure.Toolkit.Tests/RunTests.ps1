# Pester can be installed from
# http://www.powershellmagazine.com/2014/03/12/get-started-with-pester-powershell-unit-testing-framework/

#Add-AzureAccount
#Select-AzureSubscription "subscription"

# Run all tests
Invoke-Pester -Script "$PSScriptRoot"

# Run specific tests
#Invoke-Pester -Script "$PSScriptRoot\Azure.ToolKit.IAAS.Management.Tests.ps1"



