# linux-mips-xip — Execute-In-Place Linux kernel for MIPS

A working implementation of `CONFIG_XIP_KERNEL` for `arch/mips` on
**Linux 6.12.34**, booting in QEMU malta with the kernel's code
**executing directly from flash** — no copy to RAM, no decompression.

Mainline Linux supports XIP kernels only on ARM and RISC-V. This patch
series brings it to MIPS, where it is arguably a *better* fit: MIPS
KSEG0/KSEG1 are unmapped segments, so flash below 512 MiB is directly
CPU-addressable and **no page-table fixups are needed** (RISC-V needs
`xip_fixup.h` relocation games; MIPS needs none).

**Measured result** (identical config, QEMU malta, 256 MiB RAM):

| Kernel              | RAM reserved | RAM available |
|---------------------|-------------:|--------------:|
| Stock (RAM-loaded)  |        6436K |       255420K |
| **XIP (this repo)** |    **4132K** |   **257724K** |

**→ XIP frees 2304 KiB of RAM** — the flash-resident
`.text`/`.rodata`/`.init.text`. On routers with 8–16 MiB of RAM (e.g.
TP-Link Archer C54, the device that motivated this work), that is a
decisive fraction of the total memory budget.

## What boots

```
qemu-system-mipsel -M malta -cpu 24Kf -m 256 -bios build/out/xip-bios.bin -nographic
```

Full Linux boot from the emulated NOR flash: PCI enumeration, 16550
serial console, initmem reclaim, then a built-in initramfs **PID 1
runs as a real userspace ELF process** (exercising the RAM-resident,
runtime-generated TLB handlers) and powers the machine off cleanly.

> **Why `-bios` and not `-kernel`?** `-kernel` is a bootloader: QEMU
> copies the ELF into RAM and jumps to it — which would silently defeat
> XIP (the kernel would run from RAM like any normal boot). `-bios`
> maps the file as the malta NOR flash chip at phys `0x1FC00000`, the
> only true ROM on the board. The flash image here is a 4 KiB boot shim
> plus the kernel ROM blob; the CPU fetches kernel instructions from
> the flash device itself, exactly as it would from SPI-NOR on real
> hardware. `-bios` *is* the patched kernel — placed where XIP needs it.

## Memory layout

```
FLASH (phys 0x1FC00000, KSEG0 virt 0x9FC00000)        RAM (KSEG0)
+--------------------------------------------+        +--------------------+
| 0x0000  boot shim (GT-64120 + fake YAMON)  |        | 0x80100000 .data   |
| 0x1000  _xiprom: .text          VMA = LMA  |  copy  |   incl. uasm-      |
|         __ex_table (sorted at build time)  |  by    |   patched TLB/page |
|         .rodata (minus ro_after_init)      |  head.S|   handler buffers, |
|         .init.text  (never reclaimed)      |  ====> |   ro_after_init    |
|         __data_loc: LMA copy of RAM region | ------>| .init.data (freed) |
| _exiprom                                   |        | .bss, swapper_pg_dir|
+--------------------------------------------+        +--------------------+
```

Only `[_sdata, __init_end)` ever touches RAM; `head.S` copies it from
`__data_loc` before the first write.

## The five patches

| Patch | What it does |
|-------|--------------|
| `0001-mips-add-xip-kconfig` | `CONFIG_XIP_KERNEL` + `CONFIG_XIP_PHYS_ADDR` (32BIT && !RELOCATABLE && !MAPPED_KERNEL && !SMP) |
| `0002-mips-xip-linker-script` | `vmlinux-xip.lds.S`: ROM region VMA=LMA in flash; RAM region with LMA appended at `__data_loc`. Hand-expands asm-generic macros whose hardcoded `AT(ADDR(x) - LOAD_OFFSET)` silently resets LMAs |
| `0003-mips-head-xip-data-copy` | `head.S` copies writable data flash→RAM before `.bss`/firmware-arg use |
| `0004-mips-setup-xip-memblock` | memblock/resource accounting: only `[_sdata, _end)` is RAM-resident |
| `0005-mips-mm-xip-patchable-text` | The hard part: TLB handlers and `clear_page`/`copy_page` are **uasm-generated at boot** into `.text` buffers — under XIP those writes hit ROM and vanish. Moves the buffers to a RAM section (`.data..xip_patchable_text`), reached via ROM trampolines because `jal` (R_MIPS_26) cannot cross the 256 MiB jump segment between flash (`0x9fcxxxxx`) and RAM (`0x80xxxxxx`) |

## Quick start

Dependencies (Debian/Ubuntu — no MIPS gcc needed, the kernel builds
with clang):

```sh
sudo apt install clang llvm lld binutils-mipsel-linux-gnu \
                 qemu-system-mips flex bison bc cpio xz-utils \
                 libssl-dev libelf-dev
```

Build and test everything (downloads linux-6.12.34, applies patches,
builds kernel + shim + initramfs, assembles the flash image):

```sh
make            # build/out/xip-bios.bin
make verify     # static XIP-layout assertions (readelf + System.map)
make test       # boot in QEMU, assert markers, expect clean poweroff
make run        # interactive boot
```

CI (`.github/workflows/ci.yml`) runs the same three steps on every
push.

## How it's tested

**`make verify`** (`tests/verify-layout.py`) proves the binary is
*actually* XIP, not just configured for it:
- a `LOAD` segment with **VMA == LMA == 0x9FC01000**, flags `R E`
- a RAM segment whose **LMA lies inside the ROM image** (data shipped
  in flash)
- every runtime-patched uasm buffer (`handle_tlbl/s/m`,
  `xip_tlbmiss_handler_setup_pgd`, `__clear_page_start`, …) at a RAM
  address, its trampoline in flash
- ROM image within the flash budget

**`make test`** (`tests/smoke-test.py`) boots the image and requires,
in order: `Linux version` → `Memory:` → `Freeing unused kernel image`
→ `XIP-USERSPACE-OK` (PID 1, a 1 KiB freestanding ELF from the
built-in initramfs, printed via raw `write(2)`) → `XIP-POWEROFF` →
**QEMU exits 0** via the PIIX4 poweroff driver. A panic, a missing
marker, or a hang fails the test. The userspace step matters: PID 1
exec means page faults served by the **RAM-resident generated TLB
handlers** — the riskiest part of the port — under real load.

## Repo layout

```
patches/     kernel patch series vs pristine v6.12.34 (apply with -p1)
configs/     xip_qemu_malta_defconfig (savedefconfig format)
shim/        4 KiB boot shim: GT-64120 init + fake YAMON + jump to kernel
userspace/   freestanding PID 1 (raw o32 syscalls, no libc)
scripts/     build-kernel / build-userspace / build-image / run-qemu
tests/       verify-layout.py, smoke-test.py
```

## Boot-shim notes (the QEMU malta gotchas)

1. QEMU stomps a board-ID word over BIOS offset `0x10` — the reset
   code branches over a reserved header hole.
2. `-bios` images are word-swapped on mipsel (BIOS assumed big-endian);
   `build-image.sh` pre-swaps, like U-Boot's `u-boot-swap.bin`.
3. The kernel assumes YAMON already programmed the GT-64120 (registers
   moved to `0x1BE00000`, PCI I/O at `0x18000000`); the shim replays
   YAMON's exact register writes, then fakes the YAMON register
   protocol (`a0..a3`: argc/argv/envp/memsize) and jumps to
   `kernel_entry` — in flash.

## Limitations / real-hardware notes

- QEMU NOR flash has RAM-like latency; on real SPI-NOR (e.g. MT7628's
  memory-mapped window at phys `0x1C000000`) instruction fetch is much
  slower — quantifying that penalty is future work.
- `!SMP`, 32-bit, fixed link address (`!RELOCATABLE`) only.
- `.init.text` stays in flash and is not reclaimed (it costs no RAM).
- Kernel modules untested under XIP (none in the test config).

## License

The kernel patches and all code in this repository are **GPL-2.0**,
the same license as the Linux kernel they modify.

