#!/bin/sh
#
# Omnom installer - NOT IMPLEMENTED.
#
# The previous version only collected a size and printed a plan, which gave a
# false impression that an installer existed. This placeholder is explicit
# until the real engine lands.

set -eu

cat >&2 <<'EOF'
omnom installer: not implemented yet.

A real installer must partition the disk (GPT with an EFI system partition),
create and format the root filesystem, unpack a built Omnom root, install a
bootloader, write /etc/fstab and create the first user. None of that exists
yet. See README.md ("Roadmap").
EOF

exit 1
