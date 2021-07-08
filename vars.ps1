# change values as needed
$name = "tfstate"
$suffix = "dbrtest"
$env:location = "westeurope"
$id = Get-Random -Minimum 1000 -Maximum 10000

$env:spName = "tfprovision-$suffix-sp"
$env:rg = "$name-$suffix-rg"
$env:tag = "$suffix"
$env:saName = "stac0$name$suffix$id"
$env:scName = "blob0$name$suffix$id"
$env:vaultName = "akv-$name-$suffix-$id"