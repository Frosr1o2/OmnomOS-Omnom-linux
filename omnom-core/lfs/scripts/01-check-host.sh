#!/usr/bin/env bash

set -e


echo "================================"
echo " Omnom Linux LFS Host Check"
echo "================================"


ARCH=$(uname -m)


if [ "$ARCH" != "x86_64" ]; then
    echo "ERROR: x86_64 required"
    exit 1
fi


echo "[OK] Architecture: $ARCH"



REQUIRED="
bash
ld
as
ar
bison
gcc
g++
make
patch
perl
python
tar
wget
xz
"

echo

echo "Checking tools..."

for TOOL in $REQUIRED
do

    if command -v "$TOOL" >/dev/null 2>&1
    then
        echo "[OK] $TOOL"
    else
        echo "[MISSING] $TOOL"
    fi

done



echo

echo "Kernel:"
uname -r


echo

echo "CPU:"
lscpu | grep "Model name" || true


echo

echo "Memory:"
free -h


echo

echo "Host check complete"
