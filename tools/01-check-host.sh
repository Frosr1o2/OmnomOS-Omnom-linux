#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="/tmp/omnom-host-check.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Omnom Linux Host Environment Check"
echo " Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="

LC_ALL=C
export LC_ALL

error_flag=0

check_version() {
    local tool="$1"
    local min_ver="$2"
    local current_ver="$3"
    
    if [ -z "${current_ver}" ]; then
        echo "[ERROR] ${tool} is NOT installed."
        error_flag=1
        return
    fi
    echo "[OK] ${tool}: ${current_ver} (min required: ${min_ver})"
}

sh_target=$(readlink -f /bin/sh)
if [[ "${sh_target}" != *bash* ]]; then
    echo "[ERROR] /bin/sh points to ${sh_target}. It MUST point to bash."
    error_flag=1
else
    echo "[OK] /bin/sh points to bash (${sh_target})"
fi

check_version "Bash" "5.1" "$(bash --version | head -n1 | cut -d" " -f4)"
check_version "Binutils" "2.38" "$(ld --version | head -n1 | awk '{print $NF}')"
check_version "Bison" "3.8" "$(bison --version | head -n1 | awk '{print $NF}')"
check_version "Coreutils" "8.32" "$(chown --version | head -n1 | awk '{print $NF}')"
check_version "Diffutils" "3.8" "$(diff --version | head -n1 | awk '{print $NF}')"
check_version "Findutils" "4.9" "$(find --version | head -n1 | awk '{print $NF}')"
check_version "Gawk" "5.1" "$(gawk --version | head -n1 | awk '{print $3}')"
check_version "GCC" "12.2" "$(gcc -dumpversion)"
check_version "G++" "12.2" "$(g++ -dumpversion)"
check_version "Glibc" "2.36" "$(ldd --version | head -n1 | awk '{print $NF}')"
check_version "Grep" "3.7" "$(grep --version | head -n1 | awk '{print $3}')"
check_version "Gzip" "1.12" "$(gzip --version | head -n1 | awk '{print $2}')"
check_version "M4" "1.4.19" "$(m4 --version | head -n1 | awk '{print $NF}')"
check_version "Make" "4.3" "$(make --version | head -n1 | awk '{print $3}')"
check_version "Patch" "2.7" "$(patch --version | head -n1 | awk '{print $2}')"
check_version "Perl" "5.36" "$(perl -V:version | awk -F"'" '{print $2}')"
check_version "Python" "3.10" "$(python3 --version | awk '{print $2}')"
check_version "Sed" "4.8" "$(sed --version | head -n1 | awk '{print $4}')"
check_version "Tar" "1.34" "$(tar --version | head -n1 | awk '{print $4}')"
check_version "Xz" "5.2" "$(xz --version | head -n1 | awk '{print $4}')"

arch=$(uname -m)
if [ "${arch}" != "x86_64" ]; then
    echo "[ERROR] Target architecture x86_64 required, found: ${arch}"
    error_flag=1
else
    echo "[OK] Architecture: x86_64"
fi

if [ ${error_flag} -ne 0 ]; then
    echo "=========================================="
    echo "[FAIL] Host environment validation failed. Install missing packages on Fedora via dnf."
    echo "=========================================="
    exit 1
fi

echo "=========================================="
echo "[SUCCESS] Host environment is ready for Omnom Linux build."
echo "=========================================="
