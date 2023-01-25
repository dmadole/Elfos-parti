
parti.prg: parti.asm include/bios.inc include/kernel.inc
	asm02 -L -b parti.asm

clean:
	-rm -f parti.lst
	-rm -f parti.bin

