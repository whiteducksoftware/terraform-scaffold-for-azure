#!/bin/bash
# used to export variables
# change values as needed

export name="tfstate"
export suffix="dev"
export spName="tfprovision-dev-sp"
export location="West Europe"

export id="$(echo $RANDOM)"

export rg="$name-$suffix-rg"
export saName="stac0$name$suffix$id"
export scName="blob0$name$suffix$id"
export vaultName="akv-$name-$suffix-$id"

