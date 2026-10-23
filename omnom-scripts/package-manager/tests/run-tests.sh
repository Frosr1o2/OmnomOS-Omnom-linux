#!/bin/sh
# Test suite for omnom-pkg.
#
# The suite is written in POSIX shell on purpose: the package manager must be
# testable on a minimal LFS system where Python is not installed.

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin=$here/../omnom-pkg

if [ ! -x "$bin" ]; then
    echo "build the package manager first: $bin not found" >&2
    exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/omnom-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

pass=0
fail=0
case_no=0
tmpdir=$work

ok() {
    pass=$((pass + 1))
    printf 'ok %d - %s\n' "$pass" "$1"
}

bad() {
    fail=$((fail + 1))
    printf 'not ok %d - %s\n' "$pass" "$1"
}

check() {
    desc=$1
    shift
    if "$@" >/dev/null 2>&1; then
        ok "$desc"
    else
        bad "$desc"
    fi
}

run_status() {
    desc=$1
    expected=$2
    shift 2
    out=$tmpdir/out
    "$@" >"$out" 2>&1
    actual=$?
    if [ "$actual" -eq "$expected" ]; then
        ok "$desc"
    else
        bad "$desc (expected exit $expected, got $actual)"
        sed 's/^/    /' "$out" | head -20
    fi
}

expect_out() {
    desc=$1
    pattern=$2
    shift 2
    out=$tmpdir/out
    if "$@" >"$out" 2>&1 && grep -q -- "$pattern" "$out"; then
        ok "$desc"
    else
        bad "$desc (missing '$pattern')"
        sed 's/^/    /' "$out" | head -20
    fi
}

# expect_msg DESC PATTERN COMMAND...
# Like expect_out but for commands that are expected to fail.
expect_msg() {
    desc=$1
    pattern=$2
    shift 2
    out=$tmpdir/out
    "$@" >"$out" 2>&1
    if grep -q -- "$pattern" "$out"; then
        ok "$desc"
    else
        bad "$desc (missing '$pattern')"
        sed 's/^/    /' "$out" | head -20
    fi
}

new_env() {
    case_no=$((case_no + 1))
    tmpdir=$work/case$case_no
    mkdir -p "$tmpdir"/state "$tmpdir"/root "$tmpdir"/repo \
             "$tmpdir"/cache "$tmpdir"/profiles "$tmpdir"/src
    export OMNOM_STATE_DIR="$tmpdir/state"
    export OMNOM_INSTALL_ROOT="$tmpdir/root"
    export OMNOM_OUR_REPO="$tmpdir/repo"
    export OMNOM_CACHE_DIR="$tmpdir/cache"
    export OMNOM_PROFILE_ROOT="$tmpdir/profiles"
    export OMNOM_CONFIG="$tmpdir/omnom.conf"
    : > "$OMNOM_CONFIG"
}

# make_pkg NAME VERSION [INSTALL_SNIPPET]
make_pkg() {
    name=$1
    version=$2
    snippet=${3:-}
    src=$tmpdir/src/$name-$version
    mkdir -p "$src"
    printf '%s %s\n' "$name" "$version" > "$src/payload.txt"
    tar -czf "$tmpdir/src/$name-$version.tar.gz" -C "$tmpdir/src" "$name-$version"
    sha=$(sha256sum "$tmpdir/src/$name-$version.tar.gz" | cut -d' ' -f1)
    {
        echo "name=$name"
        echo "version=$version"
        echo "description=Test package $name"
        echo "source=file://$tmpdir/src/$name-$version.tar.gz"
        echo "sha256=$sha"
        echo "build=true"
        if [ -n "$snippet" ]; then
            echo "install=$snippet"
        else
            echo "install=mkdir -p \"\$DESTDIR/usr/share/$name\" && cp payload.txt \"\$DESTDIR/usr/share/$name/\""
        fi
    } > "$tmpdir/repo/$name.pkg"
}

count_generations() {
    ls "$OMNOM_STATE_DIR/generations" 2>/dev/null | grep -c '^gen-' || true
}

# ---------------------------------------------------------------------------
# Basic CLI behaviour
# ---------------------------------------------------------------------------
new_env
run_status "no arguments exits 2" 2 "$bin"
expect_out "help lists commands" "Commands:" "$bin" --help
run_status "unknown option exits 2" 2 "$bin" install --nonsense
run_status "unknown command exits 2" 2 "$bin" frobnicate

# ---------------------------------------------------------------------------
# Configuration validation
# ---------------------------------------------------------------------------
new_env
printf 'DEFAULT_METHOD=bogus\n' > "$OMNOM_CONFIG"
run_status "invalid DEFAULT_METHOD is rejected" 1 "$bin" install --list

new_env
printf 'GENERATIONS_KEEP=0\n' > "$OMNOM_CONFIG"
run_status "GENERATIONS_KEEP=0 is rejected" 1 "$bin" install --list

new_env
printf 'OUR_REPO_ENABLED=maybe\n' > "$OMNOM_CONFIG"
run_status "non-boolean OUR_REPO_ENABLED is rejected" 1 "$bin" install --list

# ---------------------------------------------------------------------------
# Empty state and dry runs
# ---------------------------------------------------------------------------
new_env
expect_out "fresh state lists zero packages" "managed by Omnom (no generation): 0" "$bin" install --list
expect_out "fresh state has no generations" "no generations" "$bin" upgrade --list-generations

make_pkg hello 1.0
expect_out "search finds an OUR package" "hello" "$bin" install --search hello --our
expect_out "dry-run install prints a plan" "dry-run" "$bin" install hello --our --dry-run -y
check "dry-run created no generation" test "$(count_generations)" = "0"
check "dry-run did not touch the install root" test ! -e "$tmpdir/root/usr"

# ---------------------------------------------------------------------------
# OUR install, list, remove, rollback
# ---------------------------------------------------------------------------
expect_out "OUR install succeeds" "installed hello 1.0" "$bin" install hello --our -y
check "OUR install placed the payload" test -f "$tmpdir/root/usr/share/hello/payload.txt"
expect_out "list shows the package and backend" "hello  \[our\]" "$bin" install --list
check "install created a generation" test "$(count_generations)" = "1"
check "install updated the profile symlink" test -L "$tmpdir/profiles/current"
check "install recorded the package" grep -qx hello "$OMNOM_STATE_DIR/packages.list"
check "install wrote history" test -s "$OMNOM_STATE_DIR/history.log"

expect_out "matching version reports up to date" "is up to date" \
    "$bin" upgrade --check --our

run_status "remove succeeds" 0 "$bin" remove hello -y
check "remove deleted the payload" test ! -e "$tmpdir/root/usr/share/hello/payload.txt"
check "remove created a second generation" test "$(count_generations)" = "2"
check "remove cleared the package list" test ! -s "$OMNOM_STATE_DIR/packages.list"

expect_out "rollback restores the recorded set" "generation gen-" "$bin" rollback -y
check "rollback restored packages.list" grep -qx hello "$OMNOM_STATE_DIR/packages.list"
expect_out "rollback keeps the backend mapping" "hello  \[our\]" "$bin" install --list

# ---------------------------------------------------------------------------
# Package recipe validation
# ---------------------------------------------------------------------------
new_env
printf 'name=broken\nversion=1.0\nsource=https://example.invalid/broken.tar.gz\n' \
    > "$tmpdir/repo/broken.pkg"
expect_msg "source without sha256 is rejected" "requires 'sha256'" \
    "$bin" install broken --our --dry-run -y

rm -f "$tmpdir/repo/broken.pkg"
printf 'name=other\nversion=1.0\n' > "$tmpdir/repo/mismatch.pkg"
expect_msg "recipe file name must match name" "file name must be other.pkg" \
    "$bin" install other --our --dry-run -y

new_env
make_pkg tampered 1.0
sed -i 's/^sha256=.*/sha256=0000000000000000000000000000000000000000000000000000000000000000/' \
    "$tmpdir/repo/tampered.pkg"
run_status "sha256 mismatch fails the install" 1 "$bin" install tampered --our -y
check "tampered package left no record" test ! -d "$OMNOM_STATE_DIR/our/tampered"
check "tampered package installed no files" test ! -e "$tmpdir/root/usr/share/tampered"

# ---------------------------------------------------------------------------
# Non-interactive confirmation
# ---------------------------------------------------------------------------
new_env
make_pkg noyes 1.0
run_status "install without --yes in a pipe is refused" 1 "$bin" install noyes --our
check "refused install left no record" test ! -d "$OMNOM_STATE_DIR/our/noyes"

# ---------------------------------------------------------------------------
# Upgrades and generation pruning
# ---------------------------------------------------------------------------
new_env
make_pkg app 1.0
"$bin" install app --our -y >/dev/null 2>&1
make_pkg app 2.0
expect_out "check reports the pending update" "1.0 -> 2.0" "$bin" upgrade --check --our
run_status "OUR upgrade succeeds" 0 "$bin" upgrade our -y
check "upgrade recorded the new version" \
    grep -qx 2.0 "$OMNOM_STATE_DIR/our/app/version"
check "upgrade replaced the payload" \
    grep -qx "app 2.0" "$tmpdir/root/usr/share/app/payload.txt"

new_env
printf 'GENERATIONS_KEEP=2\n' > "$OMNOM_CONFIG"
make_pkg one 1.0
make_pkg two 2.0
"$bin" install one --our -y >/dev/null 2>&1
"$bin" install two --our -y >/dev/null 2>&1
"$bin" remove one --our -y >/dev/null 2>&1
check "pruning keeps only GENERATIONS_KEEP generations" test "$(count_generations)" -le 2

# ---------------------------------------------------------------------------
# Launcher scripts
# ---------------------------------------------------------------------------
new_env
unset OMNOM_PKG_BIN
expect_out "omnom-install shim reaches omnom-pkg" "managed by Omnom (no generation): 0" "$here/../omnom-install" --list
expect_out "omnom-rollback shim reaches omnom-pkg" "no generations" "$here/../omnom-rollback" --list

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
