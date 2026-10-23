#!/usr/bin/env bash
#
# Omnom Linux - download and verify the LFS source archives.
#
# Uses the manifest published for the exact LFS release and verifies every
# archive against the upstream md5sums file. Archives are never re-downloaded
# when a local copy already matches its published checksum.
#
# The previous version of this script rewrote savannah.gnu.org URLs to a GNU
# mirror, which silently broke acl, attr, libpipeline and man-db (they exist
# only on savannah), and needed tools/03-fix-missing.sh as a workaround. URL
# rewriting now happens only behind the explicit --gnu-mirror option and never
# touches savannah or sourceforge.
#
# Manifests: https://www.linuxfromscratch.org/lfs/downloads/12.4/
#
# Usage: tools/03-fetch-sources.sh [--version 12.4] [--sources DIR] [--jobs N]

set -euo pipefail

LFS_VERSION="${OMNOM_LFS_VERSION:-12.4}"
LFS_ROOT="${LFS:-/mnt/omnom}"
SOURCES_DIR="${OMNOM_SOURCES_DIR:-${LFS_ROOT}/sources}"
JOBS="$(nproc 2>/dev/null || echo 4)"
RETRIES=2
GNU_MIRROR=""
LIST_VARIANT="wget-list-sysv"

usage() {
    cat <<'EOF'
Usage: tools/03-fetch-sources.sh [options]

Options:
  --version VER      LFS release to fetch (default: 12.4)
  --sources DIR      Download directory (default: $LFS/sources or /mnt/omnom/sources)
  --jobs N           Parallel downloads (default: nproc)
  --retries N        Extra verification/retry rounds for missing files (default: 2)
  --gnu-mirror URL   Replace ftpmirror.gnu.org/ftp.gnu.org with URL (savannah is never rewritten)
  -h, --help         Show this help

Requires: wget or curl, md5sum. aria2c is used automatically when present.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) LFS_VERSION="${2:?--version needs a value}"; shift 2 ;;
        --sources) SOURCES_DIR="${2:?--sources needs a value}"; shift 2 ;;
        --jobs) JOBS="${2:?--jobs needs a value}"; shift 2 ;;
        --retries) RETRIES="${2:?--retries needs a value}"; shift 2 ;;
        --gnu-mirror) GNU_MIRROR="${2:?--gnu-mirror needs a value}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

BASE_URL="${OMNOM_LFS_BASE_URL:-https://www.linuxfromscratch.org/lfs/downloads/${LFS_VERSION}}"
MANIFEST_LIST="${SOURCES_DIR}/wget-list"
MANIFEST_MD5="${SOURCES_DIR}/md5sums"

log() { printf '[sources] %s\n' "$*"; }
die() { printf '[sources] ERROR: %s\n' "$*" >&2; exit 1; }

command -v md5sum >/dev/null 2>&1 || die "md5sum is required"
if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    die "either wget or curl is required"
fi

fetch_manifest() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 -o "${output}.tmp" "${url}" && mv -f "${output}.tmp" "${output}"
    else
        wget -q -O "${output}.tmp" "${url}" && mv -f "${output}.tmp" "${output}"
    fi
}

download_url() {
    local url="$1"
    if command -v aria2c >/dev/null 2>&1; then
        aria2c -q -j "${JOBS}" -x 8 -s 8 --connect-timeout=10 --timeout=20 \
            --auto-file-renaming=false --continue=true --dir="${SOURCES_DIR}" "${url}" \
            || true
    elif command -v wget >/dev/null 2>&1; then
        wget -q -c --tries=3 --timeout=30 --directory-prefix="${SOURCES_DIR}" "${url}" || true
    else
        curl -fsSL -s --retry 3 -C - -o "${SOURCES_DIR}/${url##*/}" "${url}" || true
    fi
}

# Prints the names of archives that are missing or fail their md5 check.
verify_sources() {
    local sum name actual
    while read -r sum name; do
        [ -n "${name:-}" ] || continue
        if [ ! -f "${SOURCES_DIR}/${name}" ]; then
            printf '%s\n' "${name}"
            continue
        fi
        actual=$(md5sum "${SOURCES_DIR}/${name}" | awk '{print $1}')
        [ "${actual}" = "${sum}" ] || printf '%s\n' "${name}"
    done < "${MANIFEST_MD5}"
}

mkdir -p "${SOURCES_DIR}"
cd "${SOURCES_DIR}"

log "LFS release:   ${LFS_VERSION}"
log "Target dir:    ${SOURCES_DIR}"

# ---------------------------------------------------------------------------
# 1. Manifests
# ---------------------------------------------------------------------------
log "Downloading manifests"
if ! fetch_manifest "${BASE_URL}/${LIST_VARIANT}" "${MANIFEST_LIST}"; then
    log "WARNING: ${LIST_VARIANT} is not published for ${LFS_VERSION}; falling back to wget-list (systemd variant)"
    LIST_VARIANT="wget-list"
    fetch_manifest "${BASE_URL}/${LIST_VARIANT}" "${MANIFEST_LIST}" \
        || die "cannot download ${BASE_URL}/${LIST_VARIANT}"
fi
fetch_manifest "${BASE_URL}/md5sums" "${MANIFEST_MD5}" \
    || die "cannot download ${BASE_URL}/md5sums"

total=$(grep -c . "${MANIFEST_LIST}" || true)
checked=$(grep -c . "${MANIFEST_MD5}" || true)
log "Manifest: ${total} archives, ${checked} with published checksums"

# ---------------------------------------------------------------------------
# 2. Build the work list (only missing or mismatching archives)
# ---------------------------------------------------------------------------
declare -A EXPECTED=()
while read -r sum name; do
    [ -n "${name:-}" ] || continue
    EXPECTED["${name}"]="${sum}"
done < "${MANIFEST_MD5}"

WORK_LIST="$(mktemp)"
trap 'rm -f "${WORK_LIST}"' EXIT

skipped=0
while read -r url; do
    [ -n "${url:-}" ] || continue
    name="${url##*/}"
    if [ -f "${SOURCES_DIR}/${name}" ]; then
        if [ -z "${EXPECTED[${name}]:-}" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        if [ "$(md5sum "${SOURCES_DIR}/${name}" | awk '{print $1}')" = "${EXPECTED[${name}]}" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        log "Checksum mismatch, re-downloading: ${name}"
        rm -f "${SOURCES_DIR}/${name}"
    fi
    if [ -n "${GNU_MIRROR}" ]; then
        printf '%s\n' "${url}" \
            | sed -e "s|^https://ftpmirror.gnu.org|${GNU_MIRROR}|" \
                  -e "s|^https://ftp.gnu.org/gnu|${GNU_MIRROR}|" \
                  -e "s|^http://ftp.gnu.org/gnu|${GNU_MIRROR}|" \
                  >> "${WORK_LIST}"
    else
        printf '%s\n' "${url}" >> "${WORK_LIST}"
    fi
done < "${MANIFEST_LIST}"

pending=$(grep -c . "${WORK_LIST}" || true)
log "Already verified: ${skipped}, to download: ${pending}"

# ---------------------------------------------------------------------------
# 3. Download, retry, verify
# ---------------------------------------------------------------------------
round=0
while :; do
    pending=$(grep -c . "${WORK_LIST}" || true)
    [ "${pending}" -eq 0 ] && break

    if [ "${round}" -eq 0 ]; then
        log "Downloading ${pending} archive(s) with ${JOBS} job(s)"
        export SOURCES_DIR JOBS
        if command -v aria2c >/dev/null 2>&1; then
            aria2c -q -j "${JOBS}" -x 8 -s 8 --connect-timeout=10 --timeout=20 \
                --auto-file-renaming=false --continue=true \
                --dir="${SOURCES_DIR}" -i "${WORK_LIST}" || true
        elif command -v wget >/dev/null 2>&1; then
            # shellcheck disable=SC2016
            xargs -r -P "${JOBS}" -n 1 sh -c \
                'wget -q -c --tries=3 --timeout=30 --directory-prefix="$1" "$2" || true' _ "${SOURCES_DIR}" < "${WORK_LIST}"
        else
            while read -r url; do download_url "${url}"; done < "${WORK_LIST}"
        fi
    else
        log "Retry round ${round}/${RETRIES}: ${pending} archive(s) still missing or corrupt"
        while read -r url; do download_url "${url}"; done < "${WORK_LIST}"
    fi

    tmp_missing="$(mktemp)"
    verify_sources > "${tmp_missing}"
    : > "${WORK_LIST}"
    while read -r name; do
        [ -n "${name:-}" ] || continue
        # Drop a partial/corrupt file so the retry starts from scratch and
        # "resume" cannot keep a bad archive alive.
        rm -f "${SOURCES_DIR}/${name}"
        # Keep the original URL for the retry round.
        grep -E "/${name//./\\.}$" "${MANIFEST_LIST}" >> "${WORK_LIST}" || true
    done < "${tmp_missing}"
    rm -f "${tmp_missing}"

    if [ "$(grep -c . "${WORK_LIST}" || true)" -eq 0 ]; then
        break
    fi
    if [ "${round}" -ge "${RETRIES}" ]; then
        break
    fi
    round=$((round + 1))
done

# ---------------------------------------------------------------------------
# 4. Final report
# ---------------------------------------------------------------------------
missing="$(mktemp)"
verify_sources > "${missing}"

unverified=0
while read -r url; do
    [ -n "${url:-}" ] || continue
    name="${url##*/}"
    if [ -z "${EXPECTED[${name}]:-}" ]; then
        unverified=$((unverified + 1))
    fi
done < "${MANIFEST_LIST}"

if [ -s "${missing}" ]; then
    printf '\n' >&2
    log "Missing or corrupt archives:" >&2
    sed 's/^/         - /' "${missing}" >&2
    log "Re-run this script to retry, or check network access to:" >&2
    log "  ${BASE_URL}" >&2
    rm -f "${missing}"
    exit 1
fi

rm -f "${missing}"
verified=$(grep -c . "${MANIFEST_MD5}" || true)
log "All ${verified} checked archives present and verified"
if [ "${unverified}" -gt 0 ]; then
    log "NOTE: ${unverified} archive(s) have no published checksum and were only checked for presence"
fi
log "Sources are ready in ${SOURCES_DIR}"
