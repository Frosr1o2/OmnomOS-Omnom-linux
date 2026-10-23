# LFS 12.4 section 5.4 - Linux API headers.
#
# The headers_install target is not used because it requires rsync; the book
# extracts the user-visible headers with "make headers" instead.

PKG_NAME=linux-headers
PKG_STAGE=toolchain
PKG_SOURCE_PREFIX=linux
PKG_DESCRIPTION="Linux kernel API headers"

build_package() {
    run_in "$SRCDIR" make mrproper
    run_in "$SRCDIR" make headers
    run sh -c "find '$SRCDIR/usr/include' -type f ! -name '*.h' -delete"
    run_in "$SRCDIR" cp -rv usr/include "$LFS/usr"
}
