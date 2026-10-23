# Omnom Linux

A small, source-based Linux distribution derived from **Linux From Scratch
12.4** (the last sysvinit release). Omnom targets low-end x86_64 machines: a
minimal runtime, SysV init and a console-first environment. A lightweight X11
desktop is the intended graphical target; Hyprland is not viable on the
target hardware.

> **Status: active source build.** The build tooling and the package manager
> are tested; chapters 5–7 are complete, chapter 8 and the kernel are in
> progress, and the bootable images are not ready yet. See
> [Status](#status) for the exact scope.

## Status

| Component | State |
| --- | --- |
| Host validation (`tools/01-check-host.sh`) | Implemented, tested on Arch Linux |
| Build environment (`tools/02-prepare-env.sh`) | Implemented |
| LFS source fetching (`tools/03-fetch-sources.sh`) | Implemented, verified against LFS 12.4 manifests |
| Chapter 5 cross-toolchain (`omnom-core/lfs/`) | Implemented: binutils pass 1, GCC pass 1, Linux headers, Glibc, libstdc++ |
| Chapter 6–8 system build | **In progress**: chapters 6–7 complete; chapter 8 is at the final GCC, `Linux 6.16.1-omnom` is built |
| Kernel 6.16.1-omnom | Built: USB/AHCI storage, ext4, squashfs, overlayfs, ISO9660, serial console and Radeon DRM |
| Package manager (`omnom-pkg`) | Implemented in C++17, 42 shell tests |
| Raw USB image (`mkusb.sh`) | **In progress**: ext4 image builder and QEMU boot test exist; image not booted yet |
| Live ISO (`mkiso.sh`) | **In progress**: squashfs/overlay initramfs exists; ISO not tested yet |
| Installer (`omnom-scripts/installer/`) | **Not implemented** (placeholder exits with an error) |
| Desktop/service configuration | Example files only (`omnom-configs/`); target is console-first |

The target is **x86_64** first; aarch64 is intended but untested.

## Requirements

### Build host

The host must satisfy LFS 12.4 chapter 2.2
(<https://www.linuxfromscratch.org/lfs/view/12.4/chapter02/hostreqs.html>).
In short: bash, binutils, bison, bzip2, coreutils, diffutils, findutils,
gawk, gcc, g++, grep, gzip, m4, make, patch, perl, python3, sed, tar,
texinfo and xz must be present. `tools/01-check-host.sh` checks all of them,
including version ceilings for binutils and GCC, `/dev/pts`, and free RAM and
disk space.

Python is required **only as an LFS host tool**; no Omnom component is
written in Python.

### Build space

* 30 GB free disk (LFS sources plus build trees),
* 8 GB RAM recommended (the check warns below that),
* `$LFS` defaults to `/mnt/omnom` and must be a dedicated directory or
  partition.

## Quick start

```sh
git clone https://github.com/Frosr1o2/OmnomOS-Omnom-linux.git
cd OmnomOS-Omnom-linux

# 1. Validate the host (exit 0 means usable; warnings are advisory).
sudo tools/01-check-host.sh

# 2. Create the lfs user, directory tree and shell profile, and the /tools link.
sudo tools/02-prepare-env.sh --root /mnt/omnom

# 3. As the lfs user: download and verify the LFS 12.4 archives.
su - lfs
cd /path/to/OmnomOS-Omnom-linux
tools/03-fetch-sources.sh

# 4. Build the chapter 5 cross-toolchain.
omnom-core/lfs/build-lfs.sh --list
omnom-core/lfs/build-lfs.sh --stage toolchain
```

After the toolchain, chapters 6 and 7 are built by the same engine; chapter 8
completes the final system and chapter 9 installs the SysV bootscripts. The
current development tree lives outside this repository because the LFS build
trees are large; only the recipes and the package manager sources are tracked.

## LFS build engine

`omnom-core/lfs/build-lfs.sh` is a bash orchestrator; every package is a
sourced shell recipe in `omnom-core/lfs/packages.d/`.

```sh
build-lfs.sh --list                     # recipes, stages, source versions
build-lfs.sh --stage toolchain          # build the whole stage
build-lfs.sh --package glibc            # build one recipe
build-lfs.sh --stage toolchain --dry-run
build-lfs.sh --package glibc --force    # ignore the completion stamp
build-lfs.sh --stage toolchain --jobs 4
```

Environment variables: `LFS` (`/mnt/omnom`), `SOURCES`
(`$LFS/sources`), `BUILD_DIR` (`$LFS/build`), `LOGS_DIR`
(`$BUILD_DIR/logs`), `STAMPS_DIR` (`$BUILD_DIR/stamps`), `LFS_TGT`
(`<arch>-lfs-linux-gnu`) and `JOBS` (online CPUs).

Each package keeps:

* a work directory in `$LFS/build/<package>`,
* a full log in `$LFS/build/logs/<package>.log`,
* a completion stamp in `$LFS/build/stamps/<package>-<version>.done`.

A recipe only declares metadata and a `build_package()` function:

```sh
PKG_NAME=example
PKG_STAGE=toolchain
PKG_SOURCE_PREFIX=example          # matches example-<version>.tar.* in SOURCES
PKG_DESCRIPTION="Example package"

build_package() {
    run_in "$SRCDIR" ./configure --prefix=/usr
    run_in "$SRCDIR" make
    run_in "$SRCDIR" make DESTDIR="$LFS" install
}
```

`run` and `run_in` print the command, honour `DRY_RUN=1`, and abort the
build when a command fails. `source_archive`, `source_version`,
`source_patch` and `extract_topdir` live in `omnom-core/lfs/lib/common.sh`.

The five chapter 5 recipes follow the commands in the LFS 12.4 book verbatim
(sections 5.2-5.6); versions are taken from the archive file names instead of
being hard-coded.

## Package manager

`omnom-pkg` is a single C++17 binary. It is deliberately built with the GCC
that LFS already produces: no Rust toolchain, no interpreter, no daemon and
no external libraries.

### Build and install

```sh
cd omnom-scripts/package-manager
make                 # builds ./omnom-pkg
make test            # shell test suite (42 checks)
sudo make install    # binary -> /usr/libexec/omnom, shims -> /usr/bin
```

`omnom-install`, `omnom-remove`, `omnom-upgrade` and `omnom-rollback` are
POSIX shell shims that locate `omnom-pkg` and pass the subcommand. The binary
can also be called directly: `omnom-pkg install firefox`.

### Backends

| Backend | Detect with | Priority |
| --- | --- | --- |
| DNF (RPM) | `dnf` | 10 |
| pacman (Arch) | `pacman` | 20 |
| APT (Debian) | `apt-get` | 25 |
| AUR | `yay` or `paru` | 30 |
| OUR (Omnom User Repository) | `OUR_REPO` directory exists | 40 |
| Portage (source) | `emerge` | 50 |

For a package, Omnom first probes which available backends actually know it
(`dnf info`, `pacman -Si`, `apt-cache show`, `yay -Si`, `emerge -p`) and, at
install time, falls back through the remaining backends if one fails. The
chosen backend is remembered per package in `managed.list`.

### Commands

```sh
omnom-install firefox                 # auto-detect a backend
omnom-install firefox --pacman        # force one backend
omnom-install htop --our -y           # OUR build, no confirmation
omnom-install --list                  # packages managed by Omnom
omnom-install --list-all              # everything visible to each backend
omnom-install --search browser        # search all backends
omnom-install pkg --dry-run           # print the plan, change nothing

omnom-remove firefox                  # remove with the recorded backend
omnom-remove firefox --dry-run

omnom-upgrade --all                   # update the system backend and OUR
omnom-upgrade firefox                 # update one package
omnom-upgrade our                     # update all OUR packages
omnom-upgrade --check                 # list pending updates
omnom-upgrade --list-generations
omnom-upgrade --rollback
omnom-upgrade --switch gen-20261023_084858

omnom-rollback                        # switch to the previous generation
omnom-rollback gen-20261023_084858
omnom-rollback --list
```

Global options for every subcommand: `--config FILE`, `--dry-run`,
`-y/--yes`. `omnom-install` and `omnom-remove` also accept
`--dnf/--pacman/--apt/--aur/--our/--emerge`; `omnom-install` additionally
accepts `--no-generation`.

Exit codes: `0` success, `1` runtime failure, `2` usage error. Without
`--yes`, a mutation refuses to run when stdin is not a terminal.

### Configuration

`/etc/omnom/omnom.conf` (override with `OMNOM_CONFIG` or `--config`) uses
`KEY=VALUE` lines; environment variables take precedence.

```sh
STATE_DIR=/var/lib/omnom
PROFILE_ROOT=/omnom/profiles
OUR_REPO=/home/user/.config/omnom/our-repo
CACHE_DIR=/home/user/.cache/omnom
INSTALL_ROOT=/
DEFAULT_METHOD=auto        # auto, dnf, pacman, apt, aur, our, emerge
GENERATIONS_KEEP=10
OUR_REPO_ENABLED=true
CFLAGS="-O2 -march=native -pipe"
MAKEOPTS="-j$(nproc)"
DRY_RUN=false
```

Environment overrides: `OMNOM_STATE_DIR`, `OMNOM_PROFILE_ROOT`,
`OMNOM_OUR_REPO`, `OMNOM_CACHE_DIR`, `OMNOM_INSTALL_ROOT`,
`OMNOM_DEFAULT_METHOD`, `OMNOM_GENERATIONS_KEEP`, `OMNOM_OUR_REPO_ENABLED`,
`OMNOM_DRY_RUN`, `OMNOM_CONFIG`. `OMNOM_INSTALL_ROOT` prefixes every file
written by an OUR package, which is what the test suite uses.

### State and generations

```text
/var/lib/omnom/
├── generations/
│   ├── gen-20261023_084858/
│   │   ├── meta            # name, created, reason, method, parent
│   │   ├── packages.list
│   │   └── managed.list
│   ├── gen-20261023_084903/
│   └── current -> gen-20261023_084903
├── packages.list           # active package set
├── managed.list            # "package backend" pairs
├── history.log
└── our/<name>/             # files, version, depends
```

Every successful install, removal or upgrade creates a generation and prunes
old ones beyond `GENERATIONS_KEEP` (the active generation is never pruned).
`PROFILE_ROOT/current` is updated to point at the active generation.

**Rollback semantics:** switching a generation switches the recorded package
set, the backend mapping and the profile symlink. It does **not** restore file
contents. Removing a package deletes the files it installed; switching back
to an older generation will list the package again, but it must be
reinstalled to put its files back. Real file-level rollback needs a
snapshotting filesystem and is on the roadmap.

### OUR packages

An OUR package is a `<name>.pkg` file; the file name must match `name`.
Format:

```sh
name=hello
version=1.0
description=Example package
source=https://example.org/hello-1.0.tar.gz
sha256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
build=./configure --prefix=/usr && make
install=make install DESTDIR="$DESTDIR"
depends=
homepage=https://example.org/hello
```

Rules enforced by `omnom-pkg`:

* `name`, `version` are required; the file must be `<name>.pkg`;
* `source` requires a 64-character lowercase `sha256`; the archive is cached
  in `CACHE_DIR/our/`, verified, and extracted with `tar` or `unzip`;
* `build` and `install` run with `/bin/sh -c` inside the extracted source
  directory with `DESTDIR` (staging), `PREFIX=/usr`, `CFLAGS`, `CXXFLAGS` and
  `MAKEFLAGS` set;
* files staged under `DESTDIR` are copied into `INSTALL_ROOT` and recorded;
* `depends` is recorded but **not resolved automatically** yet.

Source downloads use `curl`, falling back to `wget`; checksums use
`sha256sum` (or `shasum -a 256`). These tools are part of the LFS base
system, which keeps the package manager binary small.

### Footprint

`make size` on x86_64 with GCC 16.2:

```text
1379224  omnom-pkg
1150368  omnom-pkg (stripped)
```

`ldd` reports only `libc.so.6` and `libm.so.6`: libstdc++ and libgcc are
linked statically. Compilation uses `-O2 -DNDEBUG -mtune=generic`
(not `-march=native`, so one binary runs everywhere),
`-ffunction-sections -fdata-sections`, `-Wl,--gc-sections`, and the installed
binary is stripped. There is no service, cache daemon or interpreter at
runtime.

## Repository layout

```text
tools/                        host check, environment prep, source fetching
omnom-core/lfs/
├── build-lfs.sh              build orchestrator
├── lib/common.sh             shared recipe helpers
└── packages.d/               chapter 5 recipes
omnom-scripts/package-manager/
├── src/                      C++17 sources
├── tests/run-tests.sh        shell test suite
└── Makefile
omnom-scripts/installer/      installer placeholder
iso/                          ISO builder placeholder
omnom-configs/                example fish, kitty, X11/sysctl and service files
```

## Roadmap

1. ~~Chapter 6 recipes (temporary system) and chapter 7 (chroot and temporary
   tools).~~ Complete.
2. Chapter 8 final system, SysV bootscripts and a kernel/initramfs. The kernel
   is built; the final GCC, bootscripts and image boot tests are in progress.
3. File-level rollback on a snapshotting filesystem, dependency resolution
   for OUR packages and package signing.
4. A real ISO builder (squashfs + GRUB) and an installer. The squashfs/overlay
   initramfs and the ISO builder exist; boot testing is pending.
5. Wire the example desktop configuration into a default profile.

## License

GPL-3.0. See `LICENSE`.
