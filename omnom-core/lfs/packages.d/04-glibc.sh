# LFS 12.4 section 5.5 - Glibc.
#
# Installs the C library into $LFS, adds the dynamic loader symlinks and
# patches ldd so it works inside the target root.

PKG_NAME=glibc
PKG_STAGE=toolchain
PKG_SOURCE_PREFIX=glibc
PKG_DESCRIPTION="GNU C Library"

build_package() {
    case "$(uname -m)" in
        i?86)
            run ln -sfv ld-linux.so.2 "$LFS/lib/ld-lsb.so.3"
            ;;
        x86_64)
            run ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64"
            run ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
            ;;
    esac

    glibc_patch=$(source_patch 'glibc-*-fhs-1.patch') ||
        die "cannot find the Glibc FHS patch"
    run_in "$SRCDIR" patch -Np1 -i "$glibc_patch"
    run_in "$SRCDIR" mkdir -v build
    printf '+ echo "rootsbindir=/usr/sbin" > %s/build/configparms\n' "$SRCDIR"
    if [ "${DRY_RUN:-0}" -eq 0 ]; then
        printf 'rootsbindir=/usr/sbin\n' > "$SRCDIR/build/configparms"
    fi

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        build_guess='$(../scripts/config.guess)'
    else
        build_guess=$(cd "$SRCDIR/build" && ../scripts/config.guess) ||
            die "cannot run scripts/config.guess"
    fi

    run_in "$SRCDIR/build" ../configure          \
        --prefix=/usr                            \
        --host="$LFS_TGT"                        \
        --build="$build_guess"                   \
        --disable-nscd                           \
        libc_cv_slibdir=/usr/lib                 \
        --enable-kernel=5.4
    run_in "$SRCDIR/build" make
    run_in "$SRCDIR/build" make DESTDIR="$LFS" install
    run sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"
}
