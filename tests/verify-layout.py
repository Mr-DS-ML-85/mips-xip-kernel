#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Static verification that vmlinux really is an XIP layout.

Asserts, from the ELF program headers and System.map:
  1. A ROM segment with VMA == LMA at KSEG0+XIP_PHYS_ADDR, flags R E
     (kernel text genuinely linked to execute from flash).
  2. A RAM segment whose VMA is in RAM (0x80xxxxxx) but whose LMA lies
     *inside the ROM image* (writable data is shipped in flash and
     copied out by head.S).
  3. The runtime-patched uasm buffers (TLB handlers, clear/copy_page)
     live at RAM addresses, with their ROM trampolines in flash.
  4. The whole ROM image fits the QEMU malta flash/swap window.

Usage: verify-layout.py <kdir> [--cross PREFIX]
"""
import argparse
import re
import subprocess
import sys

XIP_ROM_BASE = 0x9FC01000          # KSEG0 + CONFIG_XIP_PHYS_ADDR
FLASH_BUDGET = 0x3E0000 - 0x1000   # QEMU bios swap window minus shim slot

failures = []


def check(name, cond, detail=""):
    status = "ok" if cond else "FAIL"
    print(f"  [{status:4}] {name}" + (f" — {detail}" if detail else ""))
    if not cond:
        failures.append(name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kdir")
    ap.add_argument("--cross", default="mipsel-linux-gnu-")
    args = ap.parse_args()

    vmlinux = f"{args.kdir}/vmlinux"
    out = subprocess.run([args.cross + "readelf", "-lW", vmlinux],
                         capture_output=True, text=True, check=True).stdout
    loads = []
    for line in out.splitlines():
        m = re.match(r"\s*LOAD\s+(0x\S+)\s+(0x\S+)\s+(0x\S+)\s+(0x\S+)\s+"
                     r"(0x\S+)\s+([RWE ]+?)\s+0x", line)
        if m:
            off, vaddr, paddr, filesz, memsz = (int(m.group(i), 16)
                                                for i in range(1, 6))
            loads.append((vaddr, paddr, filesz, memsz,
                          m.group(6).replace(" ", "")))
    print(f"vmlinux: {len(loads)} LOAD segments")
    for v, p, fs, ms, fl in loads:
        print(f"  VMA {v:#010x}  LMA {p:#010x}  filesz {fs:#9x}  {fl}")

    rom = [s for s in loads if s[0] == s[1] and s[0] >= XIP_ROM_BASE]
    check("ROM segment exists (VMA == LMA in flash window)", len(rom) >= 1)
    check("ROM segment starts at KSEG0+XIP_PHYS_ADDR",
          rom and rom[0][0] == XIP_ROM_BASE, f"{rom[0][0]:#x}" if rom else "")
    check("ROM segment is R E (no W)",
          rom and "E" in rom[0][4] and "W" not in rom[0][4])

    rom_end = max((s[1] + s[2] for s in loads), default=0)
    ram = [s for s in loads
           if 0x80000000 <= s[0] < 0x90000000 and s[1] != s[0]]
    check("RAM segment exists with LMA != VMA", len(ram) >= 1)
    check("RAM segment LMA lies inside the ROM image",
          ram and XIP_ROM_BASE < ram[0][1] < rom_end,
          f"LMA {ram[0][1]:#x} in [{XIP_ROM_BASE:#x},{rom_end:#x})"
          if ram else "")

    rom_size = rom_end - XIP_ROM_BASE
    check("ROM image fits flash budget", 0 < rom_size <= FLASH_BUDGET,
          f"{rom_size:#x} <= {FLASH_BUDGET:#x}")

    syms = {}
    for line in open(f"{args.kdir}/System.map"):
        addr, _, name = line.split()
        syms[name] = int(addr, 16)

    def in_ram(s):
        return s in syms and 0x80000000 <= syms[s] < 0x90000000

    def in_rom(s):
        return s in syms and syms[s] >= XIP_ROM_BASE

    for s in ("xip_tlbmiss_handler_setup_pgd", "handle_tlbl", "handle_tlbs",
              "handle_tlbm", "__clear_page_start", "__copy_page_start"):
        check(f"uasm buffer {s} is RAM-resident", in_ram(s),
              f"{syms.get(s, 0):#x}")
    for s in ("tlbmiss_handler_setup_pgd", "clear_page", "copy_page",
              "kernel_entry", "_stext"):
        check(f"{s} is flash-resident", in_rom(s), f"{syms.get(s, 0):#x}")
    check("__data_loc (data load address) is in ROM", in_rom("__data_loc"))
    check("_sdata (data link address) is in RAM", in_ram("_sdata"))

    if failures:
        print(f"\nLAYOUT VERIFICATION FAILED: {len(failures)} check(s)")
        return 1
    print("\nLAYOUT VERIFICATION PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
