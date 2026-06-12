/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Minimal freestanding PID 1 for the MIPS XIP kernel smoke test.
 *
 * No libc — raw MIPS o32 syscalls only. Built with clang
 * (--target=mipsel-linux-gnu -ffreestanding -nostdlib, see
 * scripts/build-userspace.sh) and packed into the kernel's built-in
 * initramfs (CONFIG_INITRAMFS_SOURCE).
 *
 * Prints proof-of-life markers consumed by tests/smoke-test.py, then
 * powers the machine off (PIIX4 poweroff on malta) so QEMU exits with
 * status 0 — that is what makes the boot test CI-able.
 */

/* MIPS o32: __NR_Linux = 4000 + n, number in $v0, args $a0-$a3. */
#define SYS_exit	4001
#define SYS_write	4004
#define SYS_pause	4029
#define SYS_sync	4036
#define SYS_reboot	4088

#define LINUX_REBOOT_MAGIC1	0xfee1dead
#define LINUX_REBOOT_MAGIC2	672274793
#define LINUX_REBOOT_CMD_POWER_OFF	0x4321fedc

static long xsys(long n, long a, long b, long c, long d)
{
	register long r2 __asm__("$2") = n;	/* v0: syscall number */
	register long r4 __asm__("$4") = a;
	register long r5 __asm__("$5") = b;
	register long r6 __asm__("$6") = c;
	register long r7 __asm__("$7") = d;	/* a3: also error flag out */

	__asm__ volatile("syscall"
		: "+r"(r2), "+r"(r7)
		: "r"(r4), "r"(r5), "r"(r6)
		: "$1", "$3", "$8", "$9", "$10", "$11", "$12", "$13",
		  "$14", "$15", "$24", "$25", "hi", "lo", "memory");

	return r7 ? -r2 : r2;
}

static void putstr(const char *s)
{
	unsigned long n = 0;

	while (s[n])
		n++;
	xsys(SYS_write, 1, (long)s, (long)n, 0);
}

void _start(void)
{
	putstr("\n*** XIP-USERSPACE-OK: PID 1 is alive, ELF loaded by the "
	       "flash-resident kernel ***\n");
	xsys(SYS_sync, 0, 0, 0, 0);
	putstr("*** XIP-POWEROFF: requesting power off ***\n");
	xsys(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
	     LINUX_REBOOT_CMD_POWER_OFF, 0);

	/* Poweroff driver missing? Park instead of panicking the kernel. */
	putstr("*** XIP-POWEROFF-FAILED: parking ***\n");
	for (;;)
		xsys(SYS_pause, 0, 0, 0, 0);
}
