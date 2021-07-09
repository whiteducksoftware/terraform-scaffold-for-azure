. .\vars.ps1


$configuration = Get-content .\config.json | ConvertFrom-Json

Write-Host "$configuration.name"
