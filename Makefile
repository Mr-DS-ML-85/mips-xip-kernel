# MIPS XIP kernel — end-to-end orchestration.
#
#   make            build everything (kernel + shim + flash image)
#   make verify     static layout assertions on vmlinux (readelf/System.map)
#   make test       boot the image in QEMU, assert markers + clean poweroff
#   make run        boot interactively
#   make clean      remove build outputs (keeps kernel tree + tarball)
#   make distclean  remove the whole work directory
#
# WORK can point at an existing patched tree's parent, e.g.:
#   make WORK=$(HOME)/c54-kernel test

WORK ?= $(CURDIR)/build
KVER := 6.12.34
KDIR := $(WORK)/linux-$(KVER)
OUT  := $(WORK)/out

.PHONY: all kernel image verify test run clean distclean

all: image

kernel:
	scripts/build-kernel.sh $(WORK)

image: kernel
	scripts/build-image.sh $(KDIR) $(OUT)

verify:
	tests/verify-layout.py $(KDIR)

test: verify
	tests/smoke-test.py $(OUT)/xip-bios.bin --log $(OUT)/boot.log

run:
	scripts/run-qemu.sh $(OUT)/xip-bios.bin

clean:
	rm -rf $(OUT)

distclean:
	rm -rf $(WORK)
