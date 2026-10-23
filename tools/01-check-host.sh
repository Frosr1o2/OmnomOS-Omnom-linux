#!/usr/bin/env bash
#
# Omnom Linux - host environment validation.
#
# Verifies that the build host can run the LFS 12.4 build. Minimum versions
# follow the LFS book, chapter 2.2 "Host System Requirements":
# https://www.linuxfromscratch.org/lfs/view/12.4/chapter02/hostreqs.html
#
# Exit status: 0 = ready (warnings allowed), 1 = at least one hard failure.
#
# Usage: tools/01-check-host.sh [--root DIR] [--log FILE] [--quiet]

set -uo pipefail

MIN_KERNEL="5.4"
MAX_BINUTILS="2.45"
MAX_GCC="15.2.0"
RECOMMENDED_RAM_MB=8192
RECOMMENDED_DISK_GB=30

LFS_ROOT="${LFS:-/mnt/omnom}"
LOG_FILE="/tmp/omnom-host-check.log"
QUIET=0

errors=0
warnings=0

usage() {
    cat <<'EOF'
Usage: tools/01-check-host.sh [options]

Options:
  --root DIR    LFS target directory used for free-space checks (default: $LFS or /mnt/omnom)
  --log FILE    Append output to FILE (default: /tmp/omnom-host-check.log, "" disables)
  --quiet       Only print warnings, failures and the summary
  -h, --help    Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root) LFS_ROOT="${2:?--root needs a value}"; shift 2 ;;
        --log)  LOG_FILE="${2?--log needs a value}"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -n "${LOG_FILE}" ]; then
    mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || LOG_FILE=""
fi
if [ -n "${LOG_FILE}" ]; then
    exec > >(tee -a "${LOG_FILE}") 2>&1
fi

if [ -t 1 ]; then
    C_RESET=$'\033[0m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_FAIL=$'\033[31m'; C_HEAD=$'\033[1m'
else
    C_RESET=""; C_OK=""; C_WARN=""; C_FAIL=""; C_HEAD=""
fi

section()  { printf '\n%s== %s%s\n' "${C_HEAD}" "$*" "${C_RESET}"; }
ok()    { [ "${QUIET}" -eq 1 ] || printf '%s[ OK ]%s %s\n' "${C_OK}" "${C_RESET}" "$*"; }
warn()  { warnings=$((warnings + 1)); printf '%s[WARN]%s %s\n' "${C_WARN}" "${C_RESET}" "$*"; }
fail()  { errors=$((errors + 1)); printf '%s[FAIL]%s %s\n' "${C_FAIL}" "${C_RESET}" "$*"; }
info()  { [ "${QUIET}" -eq 1 ] || printf '       %s\n' "$*"; }

# version_ge CURRENT MINIMUM - true when CURRENT >= MINIMUM (GNU sort -V).
version_ge() {
    [ -n "${1:-}" ] || return 1
    [ -n "${2:-}" ] || return 0
    printf '%s\n%s\n' "$2" "$1" | sort -V -C 2>/dev/null
}

# version_gt A B - true when A > B.
version_gt() {
    version_ge "$1" "$2" && [ "$1" != "$2" ]
}

version_of() {
    local label="$1" out
    case "${label}" in
        Bash)      out=$(bash --version | head -n1) ;;
        Binutils)  out=$(ld --version | head -n1) ;;
        Bison)     out=$(bison --version | head -n1) ;;
        Coreutils) out=$(sort --version | head -n1) ;;
        Diffutils) out=$(diff --version | head -n1) ;;
        Findutils) out=$(find --version | head -n1) ;;
        Gawk)      out=$(gawk --version | head -n1) ;;
        GCC)       out=$(gcc -dumpfullversion -dumpversion 2>/dev/null || gcc -dumpversion) ;;
        "GCC (C++)") out=$(g++ -dumpfullversion -dumpversion 2>/dev/null || g++ -dumpversion) ;;
        Grep)      out=$(grep --version | head -n1) ;;
        Gzip)      out=$(gzip --version | head -n1) ;;
        M4)        out=$(m4 --version | head -n1) ;;
        Make)      out=$(make --version | head -n1) ;;
        Patch)     out=$(patch --version | head -n1) ;;
        Perl)      out=$(perl -e 'printf "%vd\n", $^V' 2>/dev/null) ;;
        Python)    out=$(python3 --version 2>&1) ;;
        Sed)       out=$(sed --version | head -n1) ;;
        Tar)       out=$(tar --version | head -n1) ;;
        Texinfo)   out=$(texi2any --version 2>/dev/null | head -n1) ;;
        Xz)        out=$(xz --version | head -n1) ;;
        *)         out="" ;;
    esac
    printf '%s\n' "${out}" | grep -E -o '[0-9]+\.[0-9]+(\.[0-9]+)?[a-z]*' | head -n1
}

check_requirement() {
    local label="$1" min="$2" probe="$3" current
    if ! command -v "${probe}" >/dev/null 2>&1; then
        fail "${label} not found (need '${probe}' >= ${min})"
        return
    fi
    current=$(version_of "${label}")
    if [ -z "${current}" ]; then
        warn "${label}: '${probe}' present but version could not be parsed"
        return
    fi
    if version_ge "${current}" "${min}"; then
        ok "${label} ${current} (>= ${min})"
    else
        fail "${label} ${current} is too old (>= ${min} required)"
    fi
}

# The script itself needs a working coreutils; without it nothing else works.
if ! command -v sort >/dev/null 2>&1 || ! sort --version-sort </dev/null >/dev/null 2>&1; then
    printf 'FATAL: coreutils with --version-sort support is required to run this check.\n' >&2
    exit 1
fi

printf '%s==========================================%s\n' "${C_HEAD}" "${C_RESET}"
printf '%s Omnom Linux host check%s\n' "${C_HEAD}" "${C_RESET}"
printf ' Host:  %s (%s)\n' "$(uname -srm)" "$(uname -o 2>/dev/null || echo unknown)"
printf ' Date:  %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
printf ' Log:   %s\n' "${LOG_FILE:-<disabled>}"
printf '%s==========================================%s\n' "${C_HEAD}" "${C_RESET}"

section "Toolchain versions"
while IFS='|' read -r label min probe; do
    [ -n "${label}" ] || continue
    check_requirement "${label}" "${min}" "${probe}"
done <<'REQ'
Coreutils|8.1|sort
Bash|3.2|bash
Binutils|2.13.1|ld
Bison|2.7|bison
Diffutils|2.8.1|diff
Findutils|4.2.31|find
Gawk|4.0.1|gawk
GCC|5.4|gcc
GCC (C++)|5.4|g++
Grep|2.5.1a|grep
Gzip|1.3.12|gzip
M4|1.4.10|m4
Make|4.0|make
Patch|2.5.4|patch
Perl|5.8.8|perl
Python|3.4|python3
Sed|4.1.5|sed
Tar|1.22|tar
Texinfo|5.0|texi2any
Xz|5.0.0|xz
REQ

section "Untested-but-working version ceilings"
binutils_version=$(version_of Binutils)
gcc_version=$(version_of "GCC (C++)")
if [ -n "${binutils_version}" ] && version_gt "${binutils_version}" "${MAX_BINUTILS}"; then
    warn "Binutils ${binutils_version} is newer than ${MAX_BINUTILS}; LFS 12.4 does not test it"
else
    ok "Binutils within tested range (<= ${MAX_BINUTILS})"
fi
if [ -n "${gcc_version}" ] && version_gt "${gcc_version}" "${MAX_GCC}"; then
    warn "GCC ${gcc_version} is newer than ${MAX_GCC}; LFS 12.4 does not test it"
else
    ok "GCC within tested range (<= ${MAX_GCC})"
fi

section "Required command aliases"
# The LFS book accepts a symlink or a small wrapper script for each alias, so
# the check inspects which program actually answers instead of the link type.
check_alias() {
    local name="$1" pattern="$2" expected="${3:-$2}" resolved answer
    if ! command -v "${name}" >/dev/null 2>&1; then
        fail "${name} is not available (should resolve to ${expected})"
        return
    fi
    resolved=$(readlink -f "$(command -v "${name}")")
    answer=$("${name}" --version 2>&1 | grep -i -m1 "${pattern}" || true)
    if [ -n "${answer}" ]; then
        ok "${name} -> ${resolved} (${expected}: ${answer})"
    else
        fail "${name} -> ${resolved} is not ${expected}"
    fi
}
check_alias sh bash bash
check_alias awk GNU gawk
check_alias yacc Bison bison

section "Kernel and kernel features"
kernel_version=$(uname -r | grep -E -o '^[0-9]+\.[0-9]+(\.[0-9]+)?')
if version_ge "${kernel_version}" "${MIN_KERNEL}"; then
    ok "Kernel ${kernel_version} (>= ${MIN_KERNEL})"
else
    fail "Kernel ${kernel_version} is too old (>= ${MIN_KERNEL} required)"
fi

if mount 2>/dev/null | grep -q 'devpts on /dev/pts' && [ -e /dev/ptmx ]; then
    ok "UNIX98 PTY support (devpts on /dev/pts, /dev/ptmx present)"
else
    fail "Kernel does not expose UNIX98 PTYs (needed by chroot builds)"
fi

section "Compiler smoke test"
if printf 'int main(void){return 0;}\n' | g++ -x c++ - -o /tmp/omnom-cc-test.$$ 2>/dev/null; then
    ok "g++ compiles and links a C++ program"
    rm -f "/tmp/omnom-cc-test.$$"
else
    fail "g++ cannot compile a C++ program (missing C++ headers or libstdc++)"
fi

section "Machine resources"
if [ "$(nproc 2>/dev/null || echo 0)" -ge 1 ] 2>/dev/null; then
    cores=$(nproc)
    if [ "${cores}" -lt 4 ]; then
        warn "${cores} CPU core(s); LFS recommends at least 4 (build will be slow)"
    else
        ok "${cores} CPU cores"
    fi
else
    fail "nproc is unavailable or returns no cores"
fi

memtotal_mb=$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
if [ "${memtotal_mb}" -lt "${RECOMMENDED_RAM_MB}" ]; then
    warn "${memtotal_mb} MB RAM; LFS recommends at least ${RECOMMENDED_RAM_MB} MB"
else
    ok "${memtotal_mb} MB RAM"
fi

probe_path="${LFS_ROOT}"
while [ ! -e "${probe_path}" ] && [ "${probe_path}" != "/" ]; do
    probe_path=$(dirname "${probe_path}")
done
free_gb=$(df -Pk "${probe_path}" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024/1024}')
if [ -z "${free_gb}" ]; then
    warn "Could not determine free space for ${LFS_ROOT}"
elif [ "${free_gb}" -lt "${RECOMMENDED_DISK_GB}" ]; then
    warn "${free_gb} GB free on ${probe_path}; ~${RECOMMENDED_DISK_GB} GB recommended for a full LFS build"
else
    ok "${free_gb} GB free on ${probe_path}"
fi

if [ -e "${LFS_ROOT}" ] && mountpoint -q "${LFS_ROOT}" 2>/dev/null; then
    ok "${LFS_ROOT} is a separate mount point"
else
    warn "${LFS_ROOT} is not a separate mount point; a dedicated partition is strongly recommended"
fi

section "Download tools (tools/03-fetch-sources.sh)"
if command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1; then
    if command -v wget >/dev/null 2>&1; then
        ok "wget available"
    else
        ok "curl available (wget is optional)"
    fi
else
    fail "either wget or curl is required to fetch LFS sources"
fi
if command -v aria2c >/dev/null 2>&1; then
    ok "aria2c available (used for parallel downloads)"
else
    info "optional: aria2c not installed, downloads will use wget/curl"
fi
if command -v md5sum >/dev/null 2>&1; then
    ok "md5sum available"
else
    fail "md5sum is required to verify the downloaded archives"
fi

section "Summary"
os_id="unknown"
if [ -r /etc/os-release ]; then
    os_id=$(. /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown} ${ID_LIKE:-}")
fi
printf ' Host distribution: %s\n' "${os_id}"

if [ "${errors}" -ne 0 ]; then
    printf '%s[FAIL]%s %d error(s), %d warning(s).\n' "${C_FAIL}" "${C_RESET}" "${errors}" "${warnings}"
    case "${os_id}" in
        *arch*|*manjaro*)
            printf '       Arch:  pacman -S --needed base-devel bison gawk texinfo python wget\n' ;;
        *fedora*|*rhel*|*centos*)
            printf '       Fedora: dnf groupinstall "Development Tools"; dnf install bison gawk texinfo python3 wget\n' ;;
        *debian*|*ubuntu*)
            printf '       Debian: apt install build-essential bison gawk texinfo python3 wget\n' ;;
    esac
    exit 1
fi

printf '%s[ OK ]%s Host is ready for the Omnom Linux build (%d warning(s)).\n' "${C_OK}" "${C_RESET}" "${warnings}"
exit 0
