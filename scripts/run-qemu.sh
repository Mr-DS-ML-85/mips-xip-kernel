#!/bin/bash
# Boot the XIP flash image interactively.
# -bios maps the file as the malta NOR flash at phys 0x1FC00000 — the
# kernel executes in place from it. (-kernel would copy an ELF into RAM
# and defeat XIP entirely.)
set -euo pipefail
IMG="${1:?usage: run-qemu.sh <xip-bios.bin>}"
exec qemu-system-mipsel -M malta -cpu 24Kf -m 256 -bios "$IMG" -nographic
