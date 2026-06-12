/* Boot shim: 4 KiB at the malta reset vector. */
OUTPUT_ARCH(mips)
ENTRY(_start)

SECTIONS
{
	. = 0xBFC00000;
	.text : {
		KEEP(*(.reset))
		*(.text .text.*)
		*(.rodata .rodata.*)
	}

	ASSERT(. <= 0xBFC01000, "shim exceeds its 4 KiB flash slot")

	/DISCARD/ : {
		*(.MIPS.abiflags)
		*(.reginfo)
		*(.gnu.attributes)
		*(.pdr)
	}
}
