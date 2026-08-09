#!/usr/bin/env bash
set -euo pipefail

export LFS=/mnt/omnom

echo "=========================================="
echo " Omnom Linux: Setting up LFS Environment"
echo "=========================================="

sudo mkdir -pv $LFS/{bin,etc,lib,sbin,usr,var,tools}
case $(uname -m) in
  x86_64) sudo mkdir -pv $LFS/lib64 ;;
esac

if ! getent group lfs >/dev/null; then
    echo "[+] Creating group lfs..."
    sudo groupadd lfs
fi

if ! id -u lfs >/dev/null 2>&1; then
    echo "[+] Creating user lfs..."
    sudo useradd -s /bin/bash -g lfs -m -k /dev/null lfs
    echo "lfs:lfs" | sudo chpasswd
fi

echo "[+] Changing ownership of $LFS to user 'lfs'..."
sudo chown -v lfs $LFS/{sources,tools,bin,etc,lib,sbin,usr,var}
case $(uname -m) in
  x86_64) sudo chown -v lfs $LFS/lib64 ;;
esac

echo "[+] Configuring .bashrc for user 'lfs'..."
cat << 'PROFILE' | sudo tee /home/lfs/.bash_profile > /dev/null
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
PROFILE

cat << 'RC' | sudo tee /home/lfs/.bashrc > /dev/null
set +h
umask 022
LFS=/mnt/omnom
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
MAKEFLAGS="-j$(nproc)"
export MAKEFLAGS
RC

sudo chown -R lfs:lfs /home/lfs

echo "=========================================="
echo "[SUCCESS] Environment ready!"
echo "To switch to lfs user run: sudo su - lfs"
echo "=========================================="
