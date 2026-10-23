#!/usr/bin/env bash
#
# Omnom Linux - prepare the LFS build tree and the unprivileged build user.
#
# This is the single preparation step for the build environment. It replaces
# the previous pair of conflicting scripts (tools/02-prepare-env.sh with the
# "omnom-build" user and tools/04-setup-environment.sh with the "lfs" user).
# The layout and the environment file follow LFS 12.4, chapter 4.2-4.4:
# https://www.linuxfromscratch.org/lfs/view/12.4/chapter04/creatingminlayout.html
# https://www.linuxfromscratch.org/lfs/view/12.4/chapter04/settingenvironment.html
#
# Must be run as root. Idempotent: safe to re-run.
#
# Usage: tools/02-prepare-env.sh [--root DIR] [--user NAME] [--jobs N]

set -euo pipefail

LFS_ROOT="${LFS:-/mnt/omnom}"
BUILD_USER="${OMNOM_BUILD_USER:-lfs}"
BUILD_GROUP="${OMNOM_BUILD_GROUP:-lfs}"
JOBS="$(nproc 2>/dev/null || echo 1)"

usage() {
    cat <<'EOF'
Usage: tools/02-prepare-env.sh [options]

Options:
  --root DIR   LFS target directory (default: $LFS or /mnt/omnom)
  --user NAME  Unprivileged build user (default: lfs)
  --jobs N     Parallel make jobs written to MAKEFLAGS (default: nproc)
  -h, --help   Show this help

Must be run as root.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root) LFS_ROOT="${2:?--root needs a value}"; shift 2 ;;
        --user) BUILD_USER="${2:?--user needs a value}"; shift 2 ;;
        --jobs) JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

log()  { printf '[prepare] %s\n' "$*"; }
die()  { printf '[prepare] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "this script must run as root (it creates a user and chowns ${LFS_ROOT})"

case "${LFS_ROOT}" in
    ""|"/") die "--root must point to a dedicated directory, not '/'" ;;
esac
if [ "${LFS_ROOT}" = "$(pwd -P)" ]; then
    die "--root must not be the source repository"
fi

arch="$(uname -m)"
case "${arch}" in
    x86_64|aarch64) ;;
    *) log "WARNING: architecture ${arch} is not a primary target (x86_64/aarch64)" ;;
esac

log "LFS target:  ${LFS_ROOT}"
log "Build user:  ${BUILD_USER}:${BUILD_GROUP}"
log "Make jobs:   ${JOBS}"

# ---------------------------------------------------------------------------
# 1. Directory layout
# ---------------------------------------------------------------------------
log "Creating directory layout"
install -d -m 0755 "${LFS_ROOT}"
install -d -m 0755 "${LFS_ROOT}"/{bin,boot,dev,etc,home,lib,media,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
install -d -m 0755 "${LFS_ROOT}"/usr/{bin,include,lib,libexec,local,sbin,share,src}
install -d -m 0755 "${LFS_ROOT}"/var/{cache,lib,local,log,mail,opt,spool,tmp}
install -d -m 1777 "${LFS_ROOT}/tmp" "${LFS_ROOT}/var/tmp"
install -d -m 0755 "${LFS_ROOT}"/{sources,tools}

if [ "${arch}" = "x86_64" ]; then
    install -d -m 0755 "${LFS_ROOT}/lib64"
    install -d -m 0755 "${LFS_ROOT}/usr/lib64"
fi

# Omnom-specific state root, consumed by omnom-scripts/package-manager.
install -d -m 0755 "${LFS_ROOT}/omnom"/{store,profiles,generations}
install -d -m 0755 "${LFS_ROOT}/var/lib/omnom"

# ---------------------------------------------------------------------------
# 2. Unprivileged build user
# ---------------------------------------------------------------------------
log "Configuring build user ${BUILD_USER}"
if ! getent group "${BUILD_GROUP}" >/dev/null 2>&1; then
    groupadd "${BUILD_GROUP}"
fi
if ! id -u "${BUILD_USER}" >/dev/null 2>&1; then
    useradd -s /bin/bash -g "${BUILD_GROUP}" -m -k /dev/null "${BUILD_USER}"
    log "Created user ${BUILD_USER} (password locked; use 'su - ${BUILD_USER}' from root)"
elif [ "${BUILD_USER}" = "root" ]; then
    die "refusing to use root as the build user"
fi

build_home="$(getent passwd "${BUILD_USER}" | cut -d: -f6)"
[ -n "${build_home}" ] || die "cannot determine home directory of ${BUILD_USER}"

# ---------------------------------------------------------------------------
# 3. Environment (LFS 12.4, chapter 4.4)
# ---------------------------------------------------------------------------
log "Writing ${build_home}/.bash_profile and ${build_home}/.bashrc"

cat > "${build_home}/.bash_profile" <<'PROFILE'
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
PROFILE

cat > "${build_home}/.bashrc" <<RC
set +h
umask 022
LFS=${LFS_ROOT}
LC_ALL=POSIX
LFS_TGT=\$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:\$PATH; fi
PATH=\$LFS/tools/bin:\$PATH
CONFIG_SITE=\$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
MAKEFLAGS="-j${JOBS}"
export MAKEFLAGS
RC

chown -R "${BUILD_USER}:${BUILD_GROUP}" "${build_home}"

# ---------------------------------------------------------------------------
# 4. Ownership and /tools convenience symlink
# ---------------------------------------------------------------------------
log "Setting ownership of ${LFS_ROOT} to ${BUILD_USER}:${BUILD_GROUP}"
chown -R "${BUILD_USER}:${BUILD_GROUP}" "${LFS_ROOT}"

if [ -L /tools ]; then
    if [ "$(readlink -f /tools)" != "$(readlink -f "${LFS_ROOT}/tools")" ]; then
        die "/tools already points to $(readlink -f /tools); expected ${LFS_ROOT}/tools"
    fi
    log "/tools symlink already correct"
elif [ -e /tools ]; then
    die "/tools exists and is not a symlink; remove it manually"
else
    ln -sv "${LFS_ROOT}/tools" /
fi

log "Environment ready"
log "Next: su - ${BUILD_USER}, then run tools/03-fetch-sources.sh"
