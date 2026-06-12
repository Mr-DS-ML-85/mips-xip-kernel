#!/bin/bash
# Build the freestanding initramfs PID 1 and the gen_init_cpio list.
# Usage: build-userspace.sh <out-dir>
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: build-userspace.sh <out-dir>}"
CROSS="${CROSS:-mipsel-linux-gnu-}"
CLANG="${CLANG:-clang}"

mkdir -p "$OUT"

"$CLANG" --target=mipsel-linux-gnu -march=mips32r2 -mabi=32 -msoft-float \
	-mno-abicalls -fno-pic -ffreestanding -nostdlib -O2 -Wall -Wextra \
	-c "$TOP/userspace/init.c" -o "$OUT/init.o"
"${CROSS}ld" -EL -static -nostdlib -e _start "$OUT/init.o" -o "$OUT/init"
"${CROSS}strip" "$OUT/init"

# gen_init_cpio list: /init + the /dev/console node PID 1 needs for stdio.
cat > "$OUT/initramfs.list" <<EOF
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
file /init $OUT/init 0755 0 0
EOF

echo "init: $(stat -c%s "$OUT/init") bytes -> $OUT/initramfs.list"
