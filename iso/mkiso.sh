#!/usr/bin/env bash


set -e


echo "Building Omnom ISO"


mkarchiso \
-v \
-w work \
-o out \
iso/profile

