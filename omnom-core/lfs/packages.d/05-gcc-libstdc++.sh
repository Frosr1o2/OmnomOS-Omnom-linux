# LFS 12.4 section 5.6 - Libstdc++ from GCC.
#
# Provides the C++ standard library for the cross compiler. The include path
# uses the GCC version detected from the source archive instead of a
# hard-coded number.

PKG_NAME=gcc-libstdc++
PKG_STAGE=toolchain
PKG_SOURCE_PREFIX=gcc
PKG_DESCRIPTION="GNU C++ standard library (cross)"

build_package() {
    gcc_version=$(source_version gcc) ||
        die "cannot determine the GCC version for --with-gxx-include-dir"
    run_in "$SRCDIR" mkdir -v build

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        build_guess='$(../config.guess)'
    else
        build_guess=$(cd "$SRCDIR/build" && ../config.guess) ||
            die "cannot run config.guess"
    fi

    run_in "$SRCDIR/build" ../libstdc++-v3/configure \
        --host="$LFS_TGT"                             \
        --build="$build_guess"                        \
        --prefix=/usr                                 \
        --disable-multilib                            \
        --disable-nls                                 \
        --disable-libstdcxx-pch                       \
        --with-gxx-include-dir="/tools/$LFS_TGT/include/c++/$gcc_version"
    run_in "$SRCDIR/build" make
    run_in "$SRCDIR/build" make DESTDIR="$LFS" install

    # Libtool archives are not usable on the target system.
    for lib in stdc++ stdc++exp stdc++fs supc++; do
        run rm -fv "$LFS/usr/lib/lib$lib.la"
    done
}
