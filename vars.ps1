$id = Get-Random -Minimum 1000 -Maximum 10000

$configuration = Get-content .\config.json | ConvertFrom-Json

$env:spName = "tfprovision-$suffix-sp"
$env:rg = "$name-$suffix-rg"
$env:tag = "$suffix"
$env:saName = "stac0$name$suffix$id"
$env:scName = "blob0$name$suffix$id"
$env:vaultName = "akv-$name-$suffix-$id"