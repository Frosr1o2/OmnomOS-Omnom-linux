#!/bin/sh
#
# Shared helpers for the Omnom LFS build engine.
#
# Sourced by omnom-core/lfs/build-lfs.sh; not meant to be executed directly.
# Every helper honours DRY_RUN=1 by printing commands instead of running them.

log()  { printf '[%s] %s\n' "$(date -u '+%H:%M:%S')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date -u '+%H:%M:%S')" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date -u '+%H:%M:%S')" "$*" >&2; exit 1; }

# run CMD... - print and execute a command; abort the build on failure.
run() {
    printf '+ %s\n' "$*"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        return 0
    fi
    "$@" || die "command failed: $*"
}

# run_in DIR CMD... - run a command inside DIR.
run_in() {
    _dir="$1"; shift
    printf '+ (cd %s && %s)\n' "$_dir" "$*"
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        return 0
    fi
    ( cd "$_dir" && "$@" ) || die "command failed in $_dir: $*"
}

# source_archive PREFIX [PATTERN]
#
# Resolve exactly one archive in $SOURCES (default $LFS/sources). The default
# pattern excludes patches such as glibc-2.42-fhs-1.patch by requiring a
# numeric version and a tar suffix.
source_archive() {
    _prefix="$1"
    _pattern="${2:-${_prefix}-[0-9]*.tar.*}"
    _sources_dir="${SOURCES:-$LFS/sources}"

    set -- "$_sources_dir"/$_pattern
    if [ ! -e "$1" ]; then
        die "no archive matching $_sources_dir/$_pattern (run tools/03-fetch-sources.sh first)"
    fi
    if [ "$#" -gt 1 ]; then
        _found=""
        for _candidate in "$@"; do
            _found="$_found $_candidate"
        done
        die "ambiguous archive for '$_prefix' ($_found); set SOURCE_PATTERN in the recipe"
    fi
    printf '%s\n' "$1"
}

# source_version PREFIX - version parsed from the archive file name.
source_version() {
    _archive=$(source_archive "$1")
    _base=${_archive##*/}
    _rest=${_base#"$1"-}
    printf '%s\n' "${_rest%%.tar.*}"
}

# source_patch GLOB - resolve exactly one LFS patch in $SOURCES.
source_patch() {
    _sources_dir="${SOURCES:-$LFS/sources}"
    set -- "$_sources_dir"/$1
    if [ ! -e "$1" ]; then
        die "required patch not found: $_sources_dir/$1"
    fi
    [ "$#" -eq 1 ] || die "ambiguous patch pattern '$1'"
    printf '%s\n' "$1"
}

# extract_topdir WORKDIR - print the single top-level directory in WORKDIR.
extract_topdir() {
    _count=0
    _top=""
    for _entry in "$1"/*; do
        [ -e "$_entry" ] || continue
        _count=$((_count + 1))
        if [ -d "$_entry" ]; then
            _top="$_entry"
        fi
    done
    if [ "$_count" -ne 1 ] || [ -z "$_top" ]; then
        die "expected exactly one source directory in $1"
    fi
    printf '%s\n' "$_top"
}

# prepare_gcc_source - extract the GCC prerequisites into $SRCDIR.
#
# GCC builds its own copies of MPFR, GMP and MPC from its source tree, which is
# what LFS 12.4 section 5.3 does before configuring.
prepare_gcc_source() {
    for _pkg in mpfr gmp mpc; do
        _version=$(source_version "$_pkg") || die "cannot determine $_pkg version"
        _archive=$(source_archive "$_pkg") || die "cannot find the $_pkg archive"
        run tar -xf "$_archive" -C "$SRCDIR"
        run mv -v "$SRCDIR/$_pkg-$_version" "$SRCDIR/$_pkg"
    done

    case "$(uname -m)" in
        x86_64)
            run sed -e '/m64=/s/lib64/lib/' -i.orig "$SRCDIR/gcc/config/i386/t-linux64"
            ;;
    esac
}
