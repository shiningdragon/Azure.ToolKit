# To get latest PSScriptAnalyzer run
# Install-Module -Name PSScriptAnalyzer 

Import-Module PSScriptAnalyzer -Force
Invoke-ScriptAnalyzer -Path $PSScriptRoot -Recurse