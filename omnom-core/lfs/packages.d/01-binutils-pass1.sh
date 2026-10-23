# LFS 12.4 section 5.2 - Binutils pass 1.
#
# Cross assembler, linker and binary utilities, installed into $LFS/tools.
# Commands follow the book verbatim.

PKG_NAME=binutils-pass1
PKG_STAGE=toolchain
PKG_SOURCE_PREFIX=binutils
PKG_DESCRIPTION="Binutils pass 1 (cross binutils)"

build_package() {
    run mkdir -p "$LFS/tools"
    run_in "$SRCDIR" mkdir -v build
    run_in "$SRCDIR/build" ../configure       \
        --prefix="$LFS/tools"                 \
        --with-sysroot="$LFS"                 \
        --target="$LFS_TGT"                   \
        --disable-nls                         \
        --enable-gprofng=no                   \
        --disable-werror                      \
        --enable-new-dtags                    \
        --enable-default-hash-style=gnu
    run_in "$SRCDIR/build" make
    run_in "$SRCDIR/build" make install
}
