#!/bin/bash
# Produce the initramfs the XIP kernel embeds (CONFIG_INITRAMFS_SOURCE).
#
# Two modes:
#   * If $LWRT_ROOTFS points at a staged root filesystem directory, emit a
#     gen_init_cpio list describing it (this is how the LWRT userspace is
#     baked in — see the LWRT repo's scripts/mkimage.sh). The kernel repo
#     stays generic: it knows nothing about LWRT beyond "here is a rootfs".
#   * Otherwise fall back to the tiny freestanding demo PID 1 (userspace/init.c),
#     so the kernel repo still builds and smoke-tests on its own.
#
# Usage: build-userspace.sh <out-dir>
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: build-userspace.sh <out-dir>}"
CROSS="${CROSS:-mipsel-linux-gnu-}"
CLANG="${CLANG:-clang}"

mkdir -p "$OUT"
LIST="$OUT/initramfs.list"

if [ -n "${LWRT_ROOTFS:-}" ]; then
	ROOT="$(cd "$LWRT_ROOTFS" && pwd)"
	echo "userspace: external rootfs $ROOT"
	{
		# Directories first so every parent exists before its children/nodes.
		( cd "$ROOT" && find . -mindepth 1 -type d | sort ) | while read -r d; do
			echo "dir ${d#.} 0755 0 0"
		done
		# Regular files, carrying their on-disk mode.
		( cd "$ROOT" && find . -type f | sort ) | while read -r f; do
			m=$(stat -c '%a' "$ROOT/${f#./}")
			echo "file ${f#.} $ROOT/${f#./} 0$m 0 0"
		done
		# Symlinks (busybox-style applet links + /sbin/init).
		( cd "$ROOT" && find . -type l | sort ) | while read -r l; do
			echo "slink ${l#.} $(readlink "$ROOT/${l#./}") 0777 0 0"
		done
		# Console + null are declared explicitly: staging them as real device
		# nodes needs root, but gen_init_cpio can synthesise them unprivileged.
		echo "nod /dev/console 0600 0 0 c 5 1"
		echo "nod /dev/null 0666 0 0 c 1 3"
	} > "$LIST"
	echo "initramfs list: $LIST ($(wc -l < "$LIST") entries)"
	exit 0
fi

echo "userspace: builtin demo init (userspace/init.c)"
"$CLANG" --target=mipsel-linux-gnu -march=mips32r2 -mabi=32 -msoft-float \
	-mno-abicalls -fno-pic -ffreestanding -nostdlib -O2 -Wall -Wextra \
	-c "$TOP/userspace/init.c" -o "$OUT/init.o"
"${CROSS}ld" -EL -static -nostdlib -e _start "$OUT/init.o" -o "$OUT/init"
"${CROSS}strip" "$OUT/init"

# gen_init_cpio list: /init + the /dev/console node PID 1 needs for stdio.
cat > "$LIST" <<EOF
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
file /init $OUT/init 0755 0 0
EOF

echo "init: $(stat -c%s "$OUT/init") bytes -> $LIST"
