#!/bin/bash
#
# Omnom LFS build engine.
#
# Builds the cross-toolchain from LFS 12.4 chapter 5 using recipes from
# packages.d/. Every recipe declares its metadata and a build_package()
# function; this script handles extraction, stamps, logs and failure
# reporting, so adding a chapter only means adding recipes.
#
# Usage:
#   build-lfs.sh --list
#   build-lfs.sh --stage toolchain [--dry-run] [--force]
#   build-lfs.sh --package glibc [--dry-run] [--force]
#
# Environment:
#   LFS          target root              (default /mnt/omnom)
#   SOURCES      source archives          (default $LFS/sources)
#   BUILD_DIR    build work directories   (default $LFS/build)
#   LOGS_DIR     per-package logs         (default $BUILD_DIR/logs)
#   STAMPS_DIR   completion stamps        (default $BUILD_DIR/stamps)
#   RECIPES_DIR  recipe directory         (default ./packages.d)
#   JOBS         parallel make jobs       (default: online CPUs)
#   LFS_TGT      target triplet           (default: <arch>-lfs-linux-gnu)
#
# Exit codes: 0 success, 1 build/environment error, 2 usage error.

set -u
set -o pipefail

umask 022

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

LFS=${LFS:-/mnt/omnom}
SOURCES=${SOURCES:-$LFS/sources}
BUILD_DIR=${BUILD_DIR:-$LFS/build}
LOGS_DIR=${LOGS_DIR:-$BUILD_DIR/logs}
STAMPS_DIR=${STAMPS_DIR:-$BUILD_DIR/stamps}
RECIPES_DIR=${RECIPES_DIR:-$SCRIPT_DIR/packages.d}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
DRY_RUN=${DRY_RUN:-0}
FORCE=${FORCE:-0}

case "$(uname -m)" in
    x86_64)  DEFAULT_TGT=x86_64-lfs-linux-gnu ;;
    aarch64) DEFAULT_TGT=aarch64-lfs-linux-gnu ;;
    i?86)    DEFAULT_TGT=i686-lfs-linux-gnu ;;
    *)       DEFAULT_TGT="$(uname -m)-lfs-linux-gnu" ;;
esac
LFS_TGT=${LFS_TGT:-$DEFAULT_TGT}

export LFS SOURCES BUILD_DIR LOGS_DIR STAMPS_DIR RECIPES_DIR JOBS LFS_TGT
export DRY_RUN FORCE
export PATH="$LFS/tools/bin:$PATH"
export MAKEFLAGS="-j$JOBS"
if [ -f "$LFS/usr/share/config.site" ]; then
    export CONFIG_SITE="$LFS/usr/share/config.site"
fi

# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <mode> [options]

Modes (choose one):
  --list                  list recipes with stage and source version
  --stage NAME            build every recipe in stage NAME (e.g. toolchain)
  --package NAME          build one recipe by package name (e.g. glibc)

Options:
  --dry-run               print commands without running them
  --force                 rebuild even when a completion stamp exists
  --jobs N                parallel make jobs (default: online CPUs)
  -h, --help              show this help

Environment:
  LFS=$LFS
  SOURCES=$SOURCES
  BUILD_DIR=$BUILD_DIR
  LFS_TGT=$LFS_TGT

Archives must be present in SOURCES; run tools/03-fetch-sources.sh first.
EOF
}

usage_error() {
    printf '[build-lfs] ERROR: %s\n' "$*" >&2
    printf 'Try --help for usage.\n' >&2
    exit 2
}

# Load a recipe in the current shell. Recipes only set metadata variables and
# define build_package(), so sourcing is side-effect free.
load_recipe() {
    local file=$1
    unset PKG_NAME PKG_STAGE PKG_SOURCE_PREFIX PKG_SOURCE_PATTERN PKG_DESCRIPTION
    unset -f build_package 2>/dev/null || true
    # shellcheck disable=SC1090
    . "$file"
    [ -n "${PKG_NAME:-}" ] || die "$file: PKG_NAME is not set"
    [ -n "${PKG_STAGE:-}" ] || die "$file: PKG_STAGE is not set"
    [ -n "${PKG_SOURCE_PREFIX:-}" ] || die "$file: PKG_SOURCE_PREFIX is not set"
    declare -F build_package >/dev/null || die "$file: build_package() is not defined"
}

recipe_files() {
    local file
    for file in "$RECIPES_DIR"/*.sh; do
        [ -e "$file" ] || continue
        printf '%s\n' "$file"
    done
}

recipe_version() {
    local version
    version=$(source_version "$PKG_SOURCE_PREFIX" 2>/dev/null) || version=""
    if [ -z "$version" ]; then
        printf '(source missing)'
    else
        printf '%s' "$version"
    fi
}

list_recipes() {
    local file
    printf '%-12s %-20s %-14s %s\n' STAGE PACKAGE VERSION DESCRIPTION
    while IFS= read -r file; do
        load_recipe "$file"
        printf '%-12s %-20s %-14s %s\n' "$PKG_STAGE" "$PKG_NAME" \
            "$(recipe_version)" "${PKG_DESCRIPTION:-}"
    done <<EOF
$(recipe_files)
EOF
}

find_recipe_by_name() {
    local want=$1 file
    while IFS= read -r file; do
        load_recipe "$file"
        if [ "$PKG_NAME" = "$want" ]; then
            printf '%s\n' "$file"
            return 0
        fi
    done <<EOF
$(recipe_files)
EOF
    return 1
}

build_one() {
    local file=$1
    local archive version stamp workdir log

    load_recipe "$file"

    archive=$(source_archive "$PKG_SOURCE_PREFIX" "${PKG_SOURCE_PATTERN:-}") ||
        die "cannot resolve the source archive for $PKG_NAME"
    version=$(source_version "$PKG_SOURCE_PREFIX") ||
        die "cannot determine the version of $PKG_NAME"

    stamp="$STAMPS_DIR/$PKG_NAME-$version.done"
    if [ -f "$stamp" ] && [ "$FORCE" -eq 0 ]; then
        log "skip $PKG_NAME $version (already built; use --force to rebuild)"
        return 0
    fi

    case "$BUILD_DIR" in
        ""|"/"|"."|"..")
            die "refusing to use BUILD_DIR='$BUILD_DIR'"
            ;;
    esac

    workdir="$BUILD_DIR/$PKG_NAME"
    log "preparing $PKG_NAME $version"
    run rm -rf "$workdir"
    run mkdir -p "$workdir"
    run tar -xf "$archive" -C "$workdir"

    if [ "$DRY_RUN" -eq 1 ]; then
        SRCDIR="$workdir/<extracted-source>"
    else
        SRCDIR=$(extract_topdir "$workdir")
    fi
    export SRCDIR
    export PKG_VERSION="$version"
    export PKG_ARCHIVE="$archive"

    log "building $PKG_NAME $version"
    if [ "$DRY_RUN" -eq 1 ]; then
        ( build_package ) || die "build dry-run failed: $PKG_NAME"
    else
        mkdir -p "$LOGS_DIR" "$STAMPS_DIR"
        log="$(printf '%s' "$LOGS_DIR/$PKG_NAME.log")"
        if ! ( build_package ) 2>&1 | tee "$log"; then
            die "build failed: $PKG_NAME (see $log)"
        fi
        date -u '+%Y-%m-%dT%H:%M:%SZ' > "$stamp"
    fi
    log "done $PKG_NAME $version"
}

build_stage() {
    local stage=$1 file found=0
    while IFS= read -r file; do
        load_recipe "$file"
        if [ "$PKG_STAGE" = "$stage" ]; then
            found=1
            build_one "$file"
        fi
    done <<EOF
$(recipe_files)
EOF
    [ "$found" -eq 1 ] || die "no recipes found for stage '$stage'"
}

MODE=""
STAGE=""
PACKAGE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --list)
            MODE=list
            ;;
        --stage)
            [ "$#" -ge 2 ] || usage_error "--stage requires a value"
            MODE=stage
            STAGE=$2
            shift
            ;;
        --package)
            [ "$#" -ge 2 ] || usage_error "--package requires a value"
            MODE=package
            PACKAGE=$2
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            export DRY_RUN
            ;;
        --force)
            FORCE=1
            export FORCE
            ;;
        --jobs)
            [ "$#" -ge 2 ] || usage_error "--jobs requires a value"
            JOBS=$2
            MAKEFLAGS="-j$JOBS"
            export JOBS MAKEFLAGS
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage_error "unknown option: $1"
            ;;
    esac
    shift
done

[ -n "$MODE" ] || { usage; exit 2; }

if [ "$MODE" = list ]; then
    list_recipes
    exit 0
fi

[ -d "$RECIPES_DIR" ] || die "recipe directory not found: $RECIPES_DIR"
[ -d "$SOURCES" ] || die "sources directory not found: $SOURCES (run tools/03-fetch-sources.sh)"

case "$MODE" in
    stage)
        build_stage "$STAGE"
        ;;
    package)
        recipe=$(find_recipe_by_name "$PACKAGE") ||
            die "unknown package '$PACKAGE' (use --list)"
        build_one "$recipe"
        ;;
esac

log "completed: $MODE ${STAGE:-$PACKAGE}"
