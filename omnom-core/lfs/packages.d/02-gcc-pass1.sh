# LFS 12.4 section 5.3 - GCC pass 1.
#
# Builds a minimal cross compiler able to compile Glibc. The MPFR, GMP and
# MPC sources are unpacked into the GCC tree by prepare_gcc_source(), exactly
# as the book does before configuring.

PKG_NAME=gcc-pass1
PKG_STAGE=toolchain
PKG_SOURCE_PREFIX=gcc
PKG_DESCRIPTION="GCC pass 1 (minimal cross compiler)"

build_package() {
    prepare_gcc_source

    # libcody's configure insists on __cplusplus == 201103 exactly, which is
    # false for any newer -std=.  Relax it so GCC can be built in C++17 mode;
    # the source itself is C++11-shaped and needs C++17 to avoid char8_t.
    run sh -c "sed -i -e 's/__cplusplus != 201103/__cplusplus < 201103/g' \
                       -e 's/__cplusplus > 201103/__cplusplus < 201103/g' \
                       '$SRCDIR/libcody/configure'"
    run_in "$SRCDIR" mkdir -v build

    glibc_version=$(source_version glibc) ||
        die "cannot determine the Glibc version for --with-glibc-version"

    run_in "$SRCDIR/build" ../configure        \
        --target="$LFS_TGT"                    \
        --prefix="$LFS/tools"                  \
        --with-glibc-version="$glibc_version"  \
        --with-sysroot="$LFS"                  \
        --with-newlib                          \
        --without-headers                      \
        --enable-default-pie                   \
        --enable-default-ssp                   \
        --disable-nls                          \
        --disable-shared                       \
        --disable-multilib                     \
        --disable-threads                      \
        --disable-libatomic                    \
        --disable-libgomp                      \
        --disable-libquadmath                  \
        --disable-libssp                       \
        --disable-libvtv                       \
        --disable-libstdcxx                    \
        --enable-languages=c,c++
    # The host compiler may default to C++20, where u8"" is char8_t and the
    # bundled libcody copy in GCC 15 no longer compiles.  Force the language
    # standard the GCC 15 sources were written for.
    run_in "$SRCDIR/build" make \
        CFLAGS="-g -O2 -std=gnu17" \
        CXXFLAGS="-g -O2 -std=gnu++17"
    run_in "$SRCDIR/build" make install

    # Create the full internal limits.h from the partial one installed above.
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        printf '+ cat gcc/limitx.h gcc/glimits.h gcc/limity.h > ' 
        printf '$(dirname $LFS_TGT-gcc -print-libgcc-file-name)/include/limits.h\n'
    else
        limits="$(dirname "$("$LFS_TGT-gcc" -print-libgcc-file-name)")/include/limits.h"
        run sh -c "cat '$SRCDIR/gcc/limitx.h' '$SRCDIR/gcc/glimits.h' '$SRCDIR/gcc/limity.h' > '$limits'"
    fi
}
