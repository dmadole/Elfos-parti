
;  Copyright 2023, David S. Madole <david@madole.net>
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.


          ; Include kernal API entry points

#include include/bios.inc
#include include/kernel.inc


          ; Define non-published API elements

d_idereset: equ   0444h
d_ideread:  equ   0447h
d_idewrite: equ   044ah

null:       equ   0

          ; Executable program header

            org   2000h - 6
            dw    start
            dw    end-start
            dw    start

start:      br    entry


          ; Build information

            db    4+80h                 ; month
            db    8                     ; day
            dw    2023                  ; year
            dw    2                     ; build

            db    'See github.com/dmadole/Elfos-parti for more info',0


          ; Check minimum needed kernel version 0.4.0 in order to have
          ; heap manager available.

entry:      ldi   k_ver.1               ; pointer to installed kernel version
            phi   rd
            ldi   k_ver.0
            plo   rd

            lda   rd                    ; if major is non-zero then good
            lbnz  skipspc

            lda   rd                    ; if minor is 4 or more then good
            smi   4
            lbdf  skipspc

            sep   scall                 ; quit with error message
            dw    o_inmsg
            db    'ERROR: Needs kernel version 0.4.0 or higher',13,10,0

            sep   sret


          ; Check command-line options. Right now one of two options must
          ; be selected: -s selects single-drive mode, in which drive 0 is
          ; partitioned into drive 0, 1, 2...; -i selects interleaved mode
          ; in which drive 0 and drive 1 are partitioned into alternate
          ; virtual drives, with drive 0 the even numbers, and drive 1 odd.

skipspc:    lda   ra                    ; skip any leading spaces
            lbz   scanpar
            sdi   ' '
            lbdf  skipspc

            sep   scall                 ; otherwise its an error
            dw    o_inmsg
            db    'USAGE: parti',13,10,0

            sep   sret


          ; Output banner message first so partition display can follow

scanpar:    sep   scall                 ; display message first thing
            dw    o_inmsg
            db    'Parti Partitioning Driver Build 2 for Elf/OS',13,10,0


          ; Initialize the array that we use to track partitions as we scan
          ; for them. Each entry has the drive specifier and a 24-bit sector
          ; address, which needs to start as zero.

            ldi   offsets.1             ; get pointer to drives table
            phi   rc
            ldi   offsets.0
            plo   rc

            ldi   0e0h                  ; first drive specifier
            plo   re

clroffs:    glo   re                    ; store entry into table
            str   rc
            inc   rc

            ldi   0                     ; zero sector address
            str   rc
            inc   rc
            str   rc
            inc   rc
            str   rc
            inc   rc

            inc   re                    ; loop for all 32 drives
            glo   re
            lbnz  clroffs

            dec   re                    ; fix msb of re - important


          ; Get pointer to the partition table that will be stored into
          ; the driver in high memory.

            ldi   drives.1              ; get pointer to partition table
            phi   r9
            ldi   drives.0
            plo   r9


          ; Loop through the array searching for partitions

onepass:    ldi   offsets.1              ; get pointer to start of table
            phi   rc
            ldi   offsets.0
            plo   rc

            ldi   0
            phi   rb


nextdrv:    lda   rc                    ; get drive of first entry
            phi   r8

            shl
            lbnf  skipdrv

            lda   rc                    ; get starting sector address
            plo   r8
            lda   rc
            phi   r7
            lda   rc
            plo   r7

            ldi   buffer.1              ; get pointer to sector buffer
            phi   rf
            ldi   buffer.0
            plo   rf

            sep   scall                 ; read the sector into buffer
            dw    d_ideread
            lbdf  endpart


          ; Look in the sector and see if there is a valid filesystem 
          ; information block in what would be sector zero of the partition.

            ldi   (buffer+100h).1       ; point to volume info
            phi   rf
            ldi   (buffer+100h).0
            plo   rf

            lda   rf                    ; if non-zero then too big
            phi   rb
            lbnz  isempty

            lda   rf                    ; if 8 or higher then too big
            plo   rb
            smi   8
            lbdf  isempty

            lda   rf                    ; low two bytes can be anything
            phi   ra
            lda   rf
            plo   ra

            lda   rf                    ; filesystem type must be one
            sdi   1
            lbnz  isempty

            lda   rf                    ; skip master directory sector
            lda   rf

            inc   rf                    ; bytes not currently used
            inc   rf
            inc   rf

            lda   rf                    ; sectors per au must be eight
            sdi   8
            lbnz  isempty

            lda   rf                    ; au count can be anything
            phi   rd
            lda   rf
            plo   rd


          ; Print the partition location, type and size to the output line.

            sep   scall                 ; print elf/os partition info
            dw    prelfos


          ; We will consider a maximum-sized filesystem of 65535 AUs as being
          ; within a 256MB partition, since it's cleaner and compatible with
          ; the prior simple static partitioning scheme.

            glo   ra                    ; compare filesystem size to 7fff8h
            smi   0f8h
            ghi   ra
            smbi  0ffh
            glo   rb
            smbi  007h

            lbnf  updates               ; if less, leave it as it is

            ldi   00h                   ; if equal or more, make it 80000h
            plo   ra
            phi   ra
            ldi   08h
            plo   rb


          ; Add an entry to the partition table with the size of the current
          ; partition and the physical drive specifier.

updates:    glo   rb
            str   r9
            inc   r9

            ghi   ra
            str   r9
            inc   r9

            glo   ra
            str   r9
            inc   r9

            ghi   r8
            str   r9
            inc   r9

            ldi   1
            phi   rb


          ; Add the size of the partition to the running sector address to get
          ; the place to look for the next partition. Store this into the 
          ; physical drive table entry.

            sex   rc

            dec   rc
            glo   ra
            add
            stxd

            ghi   ra
            adc
            stxd

            glo   rb
            adc
            str   rc

            sex   r2

            lbr   skipdrv


          ; Print the basic information about this partition into a line buffer
          ; that will be output at the end of processing the partition.

prelfos:    ghi   rd
            stxd
            glo   rd
            stxd

            sep   scall
            dw    prtpart

            sep   scall
            dw    incopy
            db    ', Elf/OS, ',0

            inc   r2
            lda   r2
            shl

            ldn   r2
            adci  0
            plo   rd

            ldi   0
            adci  0
            phi   rd

            sep   scall
            dw    f_uintout

            sep   scall
            dw    incopy
            db   ' MB',0

            ldi   (buffer+138h).1
            phi   rd
            ldi   (buffer+138h).0
            plo   rd

            ldn   rd
            lbz   output

            sep   scall
            dw    incopy
            db    ', ',0

            lda   rd

cplabel:    str   rf
            inc   rf
            lda   rd
            lbnz  cplabel

            lbr   output


prempty:    sep   scall
            dw    prtpart

            sep   scall
            dw    incopy
            db    ', Unused',0

output:     sep   scall
            dw    incopy
            db    13,10,0

            ldi   0
            str   rf

            ldi   string.1
            phi   rf
            ldi   string.0
            plo   rf

            sep   scall
            dw    o_msg

            sep   sret


prtpart:    ldi   string.1              ; set pointer to start of line
            phi   rf
            ldi   string.0
            plo   rf

            sep   scall                 ; output partition label
            dw    incopy
            db    'Disk ',0

            ldi   0                     ; get partition number
            phi   rd
            glo   r9
            smi   drives.0
            shr
            shr
            plo   rd

            sep   scall                 ; output partition number
            dw    f_uintout

            sep   scall                 ; output disk label
            dw    incopy
            db    ': Unit ',0

            ghi   r8                    ; get disk number
            ani   31
            plo   rd
            ldi   0
            phi   rd

            sep   scall                 ; output disk number
            dw    f_uintout

            sep   scall                 ; output offset label
            dw    incopy
            db    ' at ',0

            glo   r8                    ; high 8 bits of offset
            plo   rd

            sep   scall                 ; output it
            dw    f_hexout2

            ghi   r7                    ; low 16 bits of offset
            phi   rd
            glo   r7
            plo   rd

            sep   scall                 ; output it
            dw    f_hexout4

            sep   sret


          ; We came across an empty partition, one without a recognizable file
          ; system in it. Display the empty partition and we will stop scanning
          ; the drive at this point, as the rest is unpartitioned space.

isempty:    dec   rc
            dec   rc
            dec   rc
            dec   rc

            ghi   r8
            ani   127
            str   rc

            inc   rc
            lbr   skipdrv


          ; Delete the entry just prior to RC by copying the rest of the table
          ; down four bytes. Stop when we hit the zero after the last entry. Do
          ; this after hitting unpartitioned space or at the end of the disk.

endpart:    dec   rc
            dec   rc
            dec   rc
            dec   rc

            ldi   0
            str   rc

            inc   rc
skipdrv:    inc   rc
            inc   rc
            inc   rc


          ; Process the next entry in the table. If the drive field is zero,
          ; then we are at the end of the table, reset the pointer to the start
          ; and try again. If still zero, the table is empty and we are done.

            glo   rc
            smi   endtabl.0
            lbnz  nextdrv

            ghi   rb
            lbnz  onepass





            ldi   offsets.1
            phi   rc
            ldi   offsets.0
            plo   rc

cpyempt:    lda   rc
            lbnz  skipemp

            inc   rc
            inc   rc
            inc   rc

            lbr   cpynext

skipemp:    ori   0e0h
            phi   r8

            lda   rc
            plo   r8
            lda   rc
            phi   r7
            lda   rc
            plo   r7

            sep   scall
            dw    prempty

            ldi   0ffh
            str   r9
            inc   r9
            str   r9
            inc   r9
            str   r9
            inc   r9

            ghi   r8
            str   r9
            inc   r9

cpynext:    glo   rc
            smi   endtabl.0
            lbnz  cpyempt


          ; Add an entry to the partition table with the size equal to the
          ; space that would be left on a maximum size (8GB) drive. The driver
          ; will pass anything matching this through to the underlying driver
          ; which will fail if its beyond the limit.

            

          ; Calculate how many entries we added to the partition table and 
          ; update the stored count that the driver will use.

alldone:    glo   r9                    ; multiply offset by four for count
            smi   drives.0
            shr
            shr
            str   r2

            ldi   count.0               ; get pointer to count and store
            plo   r9
            ldn   r2
            str   r9


          ; Allocate a page-aligned block from the heap for storage of
          ; the persistent code module. Make it permanent so it will
          ; not get cleaned up at program exit.

allocmem:   ldi   (modend-module).1     ; length of persistent module
            phi   rc
            ldi   (modend-module).0
            plo   rc

            ldi   255                   ; page-aligned
            phi   r7
            ldi   4+64                  ; permanent and named
            plo   r7

            sep   scall                 ; request memory block
            dw    o_alloc
            lbnf  gotalloc

            sep   scall                 ; return with error
            dw    o_inmsg
            db    'ERROR: Could not allocate memeory from heap',13,10,0

            sep   sret

gotalloc:   ghi   rf                    ; Offset to adjust addresses with
            smi   module.1
            stxd

          ; Copy module code into the permanent heap block

            ldi   (modend-module).1     ; length of code to copy
            phi   rb
            ldi   (modend-module).0
            plo   rb

            ldi   module.1              ; get source address
            phi   rd
            ldi   module.0
            plo   rd

copycode:   lda   rd                    ; copy code to destination address
            str   rf
            inc   rf
            dec   rc
            dec   rb
            glo   rb
            lbnz  copycode
            ghi   rb
            lbnz  copycode

            lbr   padname

padloop:    ldi   0                     ; pad name with zeros to end of block
            str   rf
            inc   rf
            dec   rc
padname:    glo   rc
            lbnz  padloop
            ghi   rc
            lbnz  padloop


          ; Update kernel hooks to point to our module code. Use the offset
          ; to the heap block at M(R2) to update module addresses to match
          ; the copy in the heap. If there is a chain address needed for a
          ; hook, copy that to the module first in the same way.
 
            ldi   high patchtbl         ; get point to table of patch points
            phi   r8
            ldi   low patchtbl
            plo   r8

            irx                         ; point module to offset on stack

ptchloop:   lda   r8                    ; get address to patch, a zero
            lbz   return                ;  msb marks end of the table
            phi   rd
            lda   r8
            plo   rd
            inc   rd

            lda   r8                    ; if chain needed, then get address,
            lbz   notchain              ;  adjust to heap memory block
            add
            phi   rf
            ldn   r8
            plo   rf
            inc   rf

            lda   rd                    ; patch chain lbr in module code
            str   rf                    ;  to existing vector address
            inc   rf
            ldn   rd
            str   rf
            dec   rd

notchain:   inc   r8                    ; get module call point, adjust to
            lda   r8                    ;  heap, and update into vector jump
            add
            str   rd
            inc   rd
            lda   r8
            str   rd

            lbr   ptchloop


          ; Copy an inline zero-terminated string to memory at RF, leaving
          ; RF pointing just past the last copied character.

incopy:     lda   r6                    ; copy each character until null
            lbz   return
            str   rf
            inc   rf
            lbr   incopy

return:     sep   sret                  ; return to caller


          ; The numbers in the partition display are right-aligned; after
          ; considering the amount of work to post-process the output of
          ; f_uintout to accomplish this, it seemed just as easy to implement
          ; a specific conversion routine for this. The number to convert is
          ; in RD and the width to right-align it in is passedin D.

uintout:    shl                         ; multiply by two bytes per entry
            plo   re

            glo   rc                    ; save for pointer register
            stxd
            ghi   rc
            stxd

            glo   re                    ; get pointer into divisor table
            sdi   divisor.0
            plo   rc
            ldi   0
            sdbi  divisor.1
            phi   rc

            sex   rc                    ; do arithmetic against table

            ldi   0                     ; loop count for dividend
            plo   re

intloop:    ldn   rc                    ; are we at the end of table
            lbnz  divide

            glo   rd                    ; if so, turn remainder into digit
            adi   '0'
            str   rf
            inc   rf

            inc   r2                    ; restore saved with leaving x=c
            lda   r2
            phi   rc
            ldn   r2
            plo   rc

            sep   sret                  ; return

divide:     glo   rd                    ; subtract dividend from table
            sm
            plo   rd
            inc   rc
            ghi   rd
            smb
            phi   rd
            dec   rc

            inc   re                    ; increment, loop until underflow
            lbdf  divide

            glo   rd                    ; add back to undo underflow
            add
            plo   rd
            inc   rc
            ghi   rd
            adc
            phi   rd
            inc   rc

            dec   re                    ; adjust count, check if non-zero
            glo   re
            lbnz  notzero

            ldi   ' '                   ; if an initial zero, store space
            str   rf
            inc   rf

            lbr   intloop               ; continue for next digit

notzero:    ani   15                    ; remove flag, conver to digit
            adi   '0'
            str   rf
            inc   rf

            ldi   16                    ; clear counter and set flag bit
            plo   re

            lbr   intloop               ; continue for next digit

            db    10000.0,10000.1       ; table of place value divisors
            db    1000.0,1000.1
            db    100.0,100.1
            db    10.0,10.1
            db    0

divisor:    equ   $+1                   ; offset as we don't need 1 divisor


          ; Table giving addresses of jump vectors we need to update, along
          ; with offset from the start of the module to repoint those to.

patchtbl:   dw    d_ideread, ideread, virread
            dw    d_idewrite, idewrit, virwrit
            dw    d_idereset, null, virrset
            db    0



            org   ($ + 255) & 0ff00h

module:   ; Start the actual module code on a new page so that it forms
          ; a block of page-relocatable code that will be copied to himem.

          ; VIRWRIT is the read routine that is hooked into d_ideread in the
          ; kernel. It calculates the virtual drive mapping and passes that
          ; through whatever the underlying driver was before it was installed.

virwrit:    glo   r3                    ; get mapped address unless invalid
            br    findvir
            bdf   restore

idewrit:    sep   scall                 ; write to the underlying driver
            dw    d_idewrite

            br    restore                ; restore and return


          ; VIRREAD is exactly the same as VIRWRIT but for reads. In either
          ; case it is the findvir subroutine that does all the work.

virread:    glo   r3                    ; get mapped address unless invalid
            br    findvir
            bdf   restore

ideread:    sep   scall                 ; read from the underlying driver
            dw    d_ideread

restore:    irx                         ; restore original sector address
            ldxa
            phi   r8
            ldxa
            plo   r8
            ldxa
            phi   r7
            ldx
            plo   r7

virrset:    sep   sret


          ; FINDDRV looks up the requested virtual drive in the partition
          ; table and adjusts the drive and sector address to the correct
          ; physical values for that drive. If the request is invalid, then
          ; DF is set. The original values of R7-R8 are pushed to the stack.

findvir:    adi   2                     ; calculate and save return address
            plo   re

            glo   r7                    ; save current sector address
            stxd
            ghi   r7
            stxd
            glo   r8
            stxd
            ghi   r8
            stxd

            glo   r9                    ; need a working register
            stxd
            ghi   r9
            stxd

            sex   r9                    ; do arithemetic against table

            ghi   r3                    ; pointer to partition table
            phi   r9
            ldi   count.0
            plo   r9

            ghi   r8                    ; get drive number requested
            ani   31

            sm                          ; fail if not in table
            bdf   findret

            add                         ; recover and multiply by four
            shl 
            shl

            adi   (drives+3).0          ; point to drive table entry
            plo   r9

            ldn   r9                    ; get physical drive number
            phi   r8

            dec   r9                    ; compare sector to drive size
            glo   r7
            sm
            dec   r9
            ghi   r7
            smb
            dec   r9
            glo   r8
            smb

            bdf   findret               ; fail if past end of drive


chekdrv:    glo   r9                    ; done if at start, leave df clear
            xri   drives.0
            bz    findret

            dec   r9                    ; point to prior entry drive

            ghi   r8                    ; skip if not same drive, leave df
            xor
            bz    samedrv

            dec   r9                    ; skip drive entry
            dec   r9
            dec   r9

            br    chekdrv               ; check next entry

samedrv:    dec   r9                    ; add size of entry to sector
            glo   r7
            add
            plo   r7

            dec   r9
            ghi   r7
            adc
            phi   r7

            dec   r9                    ; carry will be cleared after
            glo   r8
            adc
            plo   r8

            br    chekdrv               ; check next entry


findret:    sex   r2

            irx
            ldxa
            phi   r9
            ldx
            plo   r9

            glo   re
            plo   r3


          ; The drive mapping tables follows. After a count of the number of
          ; valid entries, a table follows of one entry per virtual drive, in
          ; order. Each entry is the 24-bit length of the drive plus the 8-bit
          ; real drive number (in the format E0h plus the number).
          ;
          ; Entries in the table map to the same order as on the drives, but
          ; entries from different physica drives can be intermingled. This
          ; will allow the original -s and -i options to still work. 
            
count:      db    0                     ; count of virtual drives

drives:     ds    4*32


          ; Module name for minfo to display

label:      db    0,'Parti',0

modend:   ; This is the last of what's copied to the heap.


          ; Static storage that is included in the executable size in the 
          ; header but not actually stored in the executable.

string:     ds    80                    ; buffer for single line of output

buffer:     ds    512                   ; size of one disk sector

offsets:    ds    32*4                  ; 32 drives, 4 bytes per, 1 terminator
endtabl:    ds    0

end:      ; That's all folks!



