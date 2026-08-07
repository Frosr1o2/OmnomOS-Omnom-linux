#!/usr/bin/env bash

set -euo pipefail

export OMNOM_ROOT="/mnt/omnom"
export OMNOM_USER="omnom-build"
export OMNOM_GROUP="omnom-build"

echo "[1/4] Creating target directory structure at ${OMNOM_ROOT}..."
mkdir -p "${OMNOM_ROOT}"/{sources,tools,omnom/store,omnom/profiles,omnom/generations}
chmod -v a+wt "${OMNOM_ROOT}/sources"

echo "[2/4] Setting up build user and group..."
if ! getent group "${OMNOM_GROUP}" >/dev/null 2>&1; then
    groupadd "${OMNOM_GROUP}"
fi

if ! id -u "${OMNOM_USER}" >/dev/null 2>&1; then
    useradd -s /bin/bash -g "${OMNOM_GROUP}" -m -k /dev/null "${OMNOM_USER}"
    echo "Set password for ${OMNOM_USER}:"
    passwd "${OMNOM_USER}"
fi

chown -v "${OMNOM_USER}" "${OMNOM_ROOT}"/{sources,tools,omnom,omnom/store,omnom/profiles,omnom/generations}

echo "[3/4] Generating environment for ${OMNOM_USER}..."
BUILD_USER_HOME=$(eval echo "~${OMNOM_USER}")

cat << 'EOF' > "${BUILD_USER_HOME}/.bash_profile"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

cat << EOF > "${BUILD_USER_HOME}/.bashrc"
set +h
umask 022
OMNOM_ROOT=${OMNOM_ROOT}
LC_ALL=POSIX
OMNOM_TGT=x86_64-omnom-linux-gnu
PATH=/usr/bin
if [ ! -L /tools ]; then PATH=${OMNOM_ROOT}/tools/bin:\$PATH; fi
export OMNOM_ROOT LC_ALL OMNOM_TGT PATH
MAKEFLAGS="-j$(nproc)"
export MAKEFLAGS
EOF

chown "${OMNOM_USER}:${OMNOM_GROUP}" "${BUILD_USER_HOME}/.bash_profile" "${BUILD_USER_HOME}/.bashrc"

echo "[4/4] Creating symlink /tools -> ${OMNOM_ROOT}/tools..."
if [ ! -e /tools ]; then
    ln -sv "${OMNOM_ROOT}/tools" /
fi

echo "[SUCCESS] Environment prepared. Switch user via 'su - ${OMNOM_USER}' to start building the toolchain."
