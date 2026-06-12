#!/bin/bash
# Assemble the QEMU malta flash image:
#   [0x000000] 4 KiB boot shim (reset vector, GT-64120 init, fake YAMON)
#   [0x001000] XIP kernel ROM blob = objcopy of vmlinux by LMA
#              (.text/.rodata/.init.text in place + .data load copy)
# then word-swap (QEMU malta assumes big-endian BIOS images on mipsel).
#
# Usage: build-image.sh <kdir> <out-dir>
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="${1:?usage: build-image.sh <kdir> <out-dir>}"
OUT="${2:?usage: build-image.sh <kdir> <out-dir>}"
CROSS="${CROSS:-mipsel-linux-gnu-}"
CLANG="${CLANG:-clang}"

test -f "$KDIR/vmlinux" || { echo "no vmlinux in $KDIR (run build-kernel.sh)"; exit 1; }
mkdir -p "$OUT"

# 1. Kernel entry point, injected into the shim at link time.
KERNEL_ENTRY=0x$(grep -w kernel_entry "$KDIR/System.map" | awk '{print $1}')
echo "kernel_entry = $KERNEL_ENTRY"

# 2. Assemble + link the shim.
"$CLANG" --target=mipsel-linux-gnu -march=mips32r2 -mabi=32 -msoft-float \
	-mno-abicalls -fno-pic -c "$TOP/shim/shim.S" -o "$OUT/shim.o"
"${CROSS}ld" -EL -T "$TOP/shim/shim.ld" --defsym KERNEL_ENTRY="$KERNEL_ENTRY" \
	"$OUT/shim.o" -o "$OUT/shim.elf"
"${CROSS}objcopy" -O binary "$OUT/shim.elf" "$OUT/shim.bin"
SHIM_SIZE=$(stat -c%s "$OUT/shim.bin")
echo "shim: $SHIM_SIZE bytes"
test "$SHIM_SIZE" -le 4096 || { echo "shim exceeds its 4 KiB flash slot"; exit 1; }

# 3. Kernel ROM blob, laid out by LMA: exactly [_text, _exiprom).
"${CROSS}objcopy" -O binary "$KDIR/vmlinux" "$OUT/kernel-rom.bin"
ROM_SIZE=$(stat -c%s "$OUT/kernel-rom.bin")
echo "kernel ROM blob: $ROM_SIZE bytes"

# 4. Concatenate at the right flash offsets.
rm -f "$OUT/xip-flash.bin"
dd if="$OUT/shim.bin"       of="$OUT/xip-flash.bin" bs=4096 conv=sync status=none
dd if="$OUT/kernel-rom.bin" of="$OUT/xip-flash.bin" bs=4096 seek=1    status=none
TOTAL=$(stat -c%s "$OUT/xip-flash.bin")
echo "flash image: $TOTAL bytes ($(printf 0x%x "$TOTAL"))"
# QEMU malta only byte-swaps the first 0x3e0000 bytes of the BIOS.
test "$TOTAL" -le $((0x3e0000)) || { echo "image exceeds QEMU swap window"; exit 1; }

# 5. Word-swap for QEMU's big-endian BIOS assumption on mipsel.
python3 - "$OUT/xip-flash.bin" "$OUT/xip-bios.bin" <<'EOF'
import sys
data = bytearray(open(sys.argv[1], 'rb').read())
data += b'\0' * (-len(data) % 4)
out = bytearray(len(data))
for i in range(0, len(data), 4):
    out[i:i+4] = data[i:i+4][::-1]
open(sys.argv[2], 'wb').write(out)
EOF

echo "==> done: $OUT/xip-bios.bin"
echo "run: $TOP/scripts/run-qemu.sh $OUT/xip-bios.bin"
