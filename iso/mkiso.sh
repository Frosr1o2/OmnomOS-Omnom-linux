#!/bin/sh
#
# Omnom ISO builder - NOT IMPLEMENTED.
#
# The distribution does not have a bootable system yet (LFS chapters 6-10),
# so there is nothing to put on an ISO. This placeholder replaces the previous
# call to mkarchiso, which belongs to Arch Linux and cannot build an LFS image.
#
# A real implementation will need, at minimum:
#   * a completed $LFS tree with a kernel and an initramfs that mounts the
#     root filesystem,
#   * squashfs-tools (mksquashfs) and grub-mkrescue/xorriso,
#   * a GRUB configuration that boots the kernel with the correct root= and
#     init= parameters,
#   * an ISO profile directory (kernel, initramfs, bootloader files).

set -eu

cat >&2 <<'EOF'
omnom iso: not implemented yet.

There is no bootable Omnom system to package: the LFS chapter 5 toolchain is
the current end of the build pipeline. See README.md ("Roadmap").
EOF

exit 1
