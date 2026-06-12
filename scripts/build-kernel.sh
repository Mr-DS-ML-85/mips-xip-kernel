#!/bin/bash
# End-to-end reproducible kernel build:
#   fetch pristine linux-6.12.34 -> apply patches/ -> configure -> compile.
# Idempotent: an existing <workdir>/linux-6.12.34 is assumed already
# patched (the patch step only runs on a fresh extract).
#
# Usage: build-kernel.sh <workdir>
# Env:   CROSS (default mipsel-linux-gnu-), CLANG (default clang), JOBS
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${1:?usage: build-kernel.sh <workdir>}"
KVER=6.12.34
CROSS="${CROSS:-mipsel-linux-gnu-}"
CLANG="${CLANG:-clang}"
JOBS="${JOBS:-$(nproc)}"

case "$WORK" in *" "*) echo "error: workdir must not contain spaces (kbuild limitation)"; exit 1;; esac
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
KDIR="$WORK/linux-$KVER"

if [ ! -d "$KDIR" ]; then
	TARBALL="$WORK/linux-$KVER.tar.xz"
	if [ ! -f "$TARBALL" ]; then
		echo "==> fetching linux-$KVER"
		curl -fL --retry 3 -o "$TARBALL" \
			"https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz"
	fi
	echo "==> extracting"
	tar -C "$WORK" -xf "$TARBALL"
	echo "==> applying XIP patch series"
	for p in "$TOP"/patches/*.patch; do
		echo "    $(basename "$p")"
		patch -d "$KDIR" -p1 --no-backup-if-mismatch -s < "$p"
	done
fi

echo "==> building initramfs userspace"
"$TOP/scripts/build-userspace.sh" "$WORK/out"

echo "==> configuring (xip_qemu_malta_defconfig)"
cp "$TOP/configs/xip_qemu_malta_defconfig" "$KDIR/arch/mips/configs/"
make -C "$KDIR" ARCH=mips CC="$CLANG" CROSS_COMPILE="$CROSS" \
	xip_qemu_malta_defconfig
"$KDIR/scripts/config" --file "$KDIR/.config" \
	--set-str INITRAMFS_SOURCE "$WORK/out/initramfs.list"
make -C "$KDIR" ARCH=mips CC="$CLANG" CROSS_COMPILE="$CROSS" olddefconfig

echo "==> compiling vmlinux"
make -C "$KDIR" ARCH=mips CC="$CLANG" CROSS_COMPILE="$CROSS" -j"$JOBS" vmlinux

echo "==> done: $KDIR/vmlinux"
