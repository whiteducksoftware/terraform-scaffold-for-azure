#!/bin/bash
# used to export variables

# change values as needed
export name="tfstate"
export suffix="prod"
export location="West Europe"

export id="$(echo $RANDOM)"

export spName="tfprovision-$suffix-sp"
export rg="$name-$suffix-rg"
export tag="$suffix"
export saName="stac0$name$suffix$id"
export scName="blob0$name$suffix$id"
export vaultName="akv-$name-$suffix-$id"
