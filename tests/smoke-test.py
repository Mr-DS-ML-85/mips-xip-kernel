#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Boot the XIP flash image in QEMU and assert the full boot chain.

Markers must appear in order on the serial console:
  1. "Linux version"                      — kernel alive, console up
  2. "Memory:"                            — memblock accounting sane
  3. "Freeing unused kernel image"        — init memory reclaim worked
  4. "XIP-USERSPACE-OK"                   — PID 1 ELF exec'd from initramfs
  5. "XIP-POWEROFF: requesting power off" — userspace reboot() reached
then QEMU must EXIT on its own (PIIX4 poweroff) with status 0.
"XIP-POWEROFF-FAILED" or a kernel panic anywhere is an instant FAIL.

Exit code: 0 pass, 1 fail. Stdlib only (CI-friendly).

Usage: smoke-test.py <xip-bios.bin> [--log boot.log] [--timeout 120]
"""
import argparse
import os
import re
import selectors
import subprocess
import sys
import time

MARKERS = [
    b"Linux version",
    b"Memory:",
    b"Freeing unused kernel image",
    b"XIP-USERSPACE-OK",
    b"XIP-POWEROFF: requesting power off",
]
FATAL = [b"XIP-POWEROFF-FAILED", b"Kernel panic", b"Oops"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--log", default="boot.log")
    ap.add_argument("--timeout", type=float, default=120.0)
    args = ap.parse_args()

    cmd = ["qemu-system-mipsel", "-M", "malta", "-cpu", "24Kf", "-m", "256",
           "-bios", args.image, "-display", "none", "-serial", "stdio",
           "-monitor", "none", "-no-reboot"]
    print("+ " + " ".join(cmd))
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT,
                            stdin=subprocess.DEVNULL)
    os.set_blocking(proc.stdout.fileno(), False)
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)

    buf = b""
    pending = list(MARKERS)
    deadline = time.monotonic() + args.timeout
    failed = None
    while time.monotonic() < deadline:
        if sel.select(timeout=0.5):
            chunk = proc.stdout.read(65536)
            if chunk:
                buf += chunk
        for f in FATAL:
            if f in buf:
                failed = f.decode()
                break
        while pending and pending[0] in buf:
            print(f"  [ok] {pending.pop(0).decode()}")
        if failed or (not pending and proc.poll() is not None):
            break
        if proc.poll() is not None and not sel.select(timeout=0.5):
            break
    sel.close()

    if proc.poll() is None:  # still running: drain grace period, then kill
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()

    with open(args.log, "wb") as f:
        f.write(buf)
    print(f"boot log: {args.log} ({len(buf)} bytes)")

    mem = re.search(rb"Memory: (\d+)K/(\d+)K available.*?(\d+)K reserved",
                    buf)
    if mem:
        avail, total, resv = (int(x) for x in mem.groups())
        print(f"  memory: {avail}K/{total}K available, {resv}K reserved")

    ok = True
    if failed:
        print(f"FAIL: fatal marker seen: {failed}")
        ok = False
    if pending:
        print("FAIL: missing markers: "
              + ", ".join(m.decode() for m in pending))
        ok = False
    if proc.returncode != 0:
        print(f"FAIL: QEMU exit code {proc.returncode} "
              "(expected clean poweroff exit 0)")
        ok = False
    print("SMOKE TEST " + ("PASSED" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
