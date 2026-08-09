#!/usr/bin/env bash
set -euo pipefail

SOURCES_DIR="/mnt/omnom/sources"
LFS_BASE="https://www.linuxfromscratch.org/lfs/downloads/12.2"

echo "=========================================="
echo " Omnom Linux Source Fetcher"
echo " Target Directory: ${SOURCES_DIR}"
echo "=========================================="

mkdir -p "${SOURCES_DIR}"
cd "${SOURCES_DIR}"

echo "[1/3] Downloading package lists..."
wget -q -N "${LFS_BASE}/wget-list-sysv" -O wget-list || wget -q -N "${LFS_BASE}/wget-list" -O wget-list
wget -q -N "${LFS_BASE}/md5sums" -O md5sums

sed -i 's|https://ftp.gnu.org/gnu|https://mirror.yandex.ru/mirrors/gnu|g' wget-list
sed -i 's|http://ftp.gnu.org/gnu|https://mirror.yandex.ru/mirrors/gnu|g' wget-list
sed -i 's|https://download.savannah.gnu.org/releases|https://mirror.yandex.ru/mirrors/gnu|g' wget-list
sed -i 's|https://prdownloads.sourceforge.net|https://downloads.sourceforge.net|g' wget-list
sed -i 's|https://www.linuxfromscratch.org/lfs/downloads/12.2|https://mirrors.kernel.org/lfs/lfs-packages/12.2|g' wget-list

echo "[2/3] Downloading source tarballs via aria2c..."
if command -v aria2c >/dev/null 2>&1; then
    aria2c -j 16 -x 8 -s 8 --connect-timeout=10 --timeout=15 -i wget-list --dir="${SOURCES_DIR}" --auto-file-renaming=false --continue=true || true
else
    wget --input-file=wget-list --continue --directory-prefix="${SOURCES_DIR}" || true
fi

echo "[3/3] Verifying package integrity..."
if md5sum -c md5sums --status 2>/dev/null; then
    echo "=========================================="
    echo "[SUCCESS] All source packages downloaded and verified."
    echo "=========================================="
else
    echo "[!] Some packages missing or broken. Running final pass with wget..."
    wget --input-file=wget-list --continue --directory-prefix="${SOURCES_DIR}" --timeout=15 --tries=3
    md5sum -c md5sums
fi
