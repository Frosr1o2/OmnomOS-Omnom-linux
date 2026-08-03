#!/usr/bin/env bash

set -e


LFS_VERSION="12.3"

BASE_URL="https://www.linuxfromscratch.org/lfs/downloads/$LFS_VERSION"

SOURCE_DIR="$(pwd)/sources"


mkdir -p "$SOURCE_DIR"


echo "================================="
echo " Omnom Linux LFS Downloader"
echo "================================="


cd "$SOURCE_DIR"



echo "[+] Downloading LFS package list"


wget -c \
https://www.linuxfromscratch.org/lfs/downloads/$LFS_VERSION/wget-list \
-O wget-list



echo "[+] Downloading sources"



wget \
--input-file=wget-list \
--continue



echo "[+] Sources downloaded"



echo
echo "Location:"
pwd


echo

echo "Next stage:"
echo "03-create-lfs-user.sh"
