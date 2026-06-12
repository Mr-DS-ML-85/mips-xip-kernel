/*
 * XIP boot shim for the QEMU malta board.
 *
 * Lives in the first 4 KiB of the boot flash (reset vector 0xBFC00000,
 * phys 0x1FC00000). The XIP Linux kernel sits right behind it at phys
 * 0x1FC01000 (CONFIG_XIP_PHYS_ADDR) and is *not copied anywhere*: we
 * fake YAMON's register protocol and jump straight into kernel_entry,
 * which executes in place from the flash window.
 *
 * YAMON boot protocol (consumed by arch/mips/fw/lib/cmdline.c and
 * mti-malta/malta-dtshim.c):
 *   a0 = argc            (must be < CKSEG0 to be considered valid)
 *   a1 = argv            (array of string pointers, >= CKSEG0)
 *   a2 = envp            (YAMON "name", "value" pointer pairs, NULL-term)
 *   a3 = memory size     (legacy; malta actually reads env "memsize")
 *
 * KERNEL_ENTRY is injected at link time with --defsym from System.map.
 */

	.set	noreorder
	.set	noat

	.section .reset, "ax"
	.globl	_start
_start:
	/* QEMU malta stomps a board-ID word over BIOS offset 0x10 after
	 * loading (hw/mips/malta.c), like a real YAMON ROM header — keep
	 * a reserved hole there.
	 */
	b	1f
	 nop				/* 0x04: delay slot */
	.word	0			/* 0x08 */
	.word	0			/* 0x0c */
	.word	0x00000420		/* 0x10: board ID, overwritten */
	.word	0			/* 0x14 */
1:
	di				/* no interrupts during bring-up */

	/*
	 * GT-64120 system controller setup, exactly as YAMON (and QEMU's
	 * -kernel mini-bootloader, hw/mips/malta.c write_bootloader) does
	 * it. Linux's malta platform code assumes this already happened:
	 * GT registers at 0x1be00000 and PCI0 I/O decoded at 0x18000000
	 * (ttyS0 = 0x18000000+0x3f8) — without it earlycon spins forever.
	 * The GT comes out of reset big-endian, so the register values
	 * (addr << 3, i.e. addr[35:21] in bits[14:0]) are byte-swapped.
	 */
	li	$t0, 0xB4000068		/* GT_ISD @ reset base 0x14000000 */
	li	$t1, 0x000000DF		/* bswap(0x1be00000 << 3): move regs */
	sw	$t1, 0($t0)
	li	$t0, 0xBBE00048		/* GT_PCI0IOLD */
	li	$t1, 0x000000C0		/* bswap(0x18000000 << 3) */
	sw	$t1, 0($t0)
	li	$t1, 0x00000040		/* GT_PCI0IOHD: bswap(0x08000000<<3) */
	sw	$t1, 8($t0)
	li	$t1, 0x00000080		/* GT_PCI0M0LD: bswap(0x10000000<<3) */
	sw	$t1, 0x10($t0)
	li	$t1, 0x0000003F		/* GT_PCI0M0HD: bswap(0x07e00000<<3) */
	sw	$t1, 0x18($t0)
	li	$t1, 0x000000C1		/* GT_PCI0M1LD: bswap(0x18200000<<3) */
	sw	$t1, 0x38($t0)
	li	$t1, 0x0000005E		/* GT_PCI0M1HD: bswap(0x0bc00000<<3) */
	sw	$t1, 0x40($t0)

	li	$a0, 2			/* argc */
	la	$a1, argv
	la	$a2, envp
	li	$a3, 0x10000000		/* legacy memsize: 256 MiB */
	la	$t9, KERNEL_ENTRY	/* from System.map via --defsym */
	jr	$t9
	 nop

	.balign	4
argv:	.word	arg0
	.word	arg1
	.word	0
envp:	.word	env0_name
	.word	env0_val
	.word	0

arg0:	.asciz	"xipshim"
arg1:	.asciz	"console=ttyS0"
env0_name:
	.asciz	"memsize"
env0_val:
	.asciz	"0x10000000"
