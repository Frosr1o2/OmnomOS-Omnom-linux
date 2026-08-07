#!/usr/bin/env bash
set -euo pipefail

SOURCES_DIR="/mnt/omnom/sources"
cd "${SOURCES_DIR}"

echo "=========================================="
echo " Omnom Linux: Downloading Missing Packages"
echo "=========================================="

rm -f attr-2.5.2.tar.gz acl-2.3.2.tar.xz libpipeline-1.5.7.tar.gz

URLS=(
    "https://download-mirror.savannah.gnu.org/releases/attr/attr-2.5.2.tar.gz"
    "https://download-mirror.savannah.gnu.org/releases/acl/acl-2.3.2.tar.xz"
    "https://download-mirror.savannah.gnu.org/releases/libpipeline/libpipeline-1.5.7.tar.gz"
)

echo "[1/2] Fetching remaining targeted sources..."
for url in "${URLS[@]}"; do
    wget --tries=5 --timeout=15 "${url}" || true
done

echo "[2/2] Final Checksum Verification..."
if md5sum -c md5sums --status 2>/dev/null; then
    echo "=========================================="
    echo "[SUCCESS] ALL SOURCES ARE READY!"
    echo "=========================================="
else
    echo "------------------------------------------"
    echo "Status of missing/broken files:"
    md5sum -c md5sums 2>&1 | grep "FAILED\|No such file" || echo "All packages verified!"
    echo "------------------------------------------"
fi
