
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

            db    1+80h                 ; month
            db    21                    ; day
            dw    2023                  ; year
            dw    1                     ; build

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
            lbz   dousage
            sdi   ' '
            lbdf  skipspc

            adi   '-'-' '               ; if not a dash then error
            lbnz  dousage

            lda   ra                    ; if an i then interleaved
            smi   'i'
            lbz   interlv

            smi   's'-'i'               ; if an s then single-drive
            lbnz  dousage

sequent:    ldi   high patchseq         ; get point to table of patch points
            phi   r8
            ldi   low patchseq
            plo   r8

            lbr   allopts               ; check the rest of line

interlv:    ldi   high patchint         ; get point to table of patch points
            phi   r8
            ldi   low patchint
            plo   r8

allopts:    lda   ra                    ; rest of line can only be spaces
            lbz   allocmem
            sdi   ' '
            lbdf  allopts

dousage:    sep   scall                 ; otherwise its an error
            dw    o_inmsg
            db    'USAGE: parti -s | -i',13,10,0
            sep   sret


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


          ; Output banner message

            sep   scall
            dw    o_inmsg
            db    'Parti Partitioning Driver Build 1 for Elf/OS',13,10,0


          ; Update kernel hooks to point to our module code. Use the offset
          ; to the heap block at M(R2) to update module addresses to match
          ; the copy in the heap. If there is a chain address needed for a
          ; hook, copy that to the module first in the same way.
 
            irx                         ; point module to offset on stack

ptchloop:   lda   r8                    ; get address to patch, a zero
            lbz   finished              ;  msb marks end of the table
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


          ; All done, exit to operating system

finished:   sep   sret


          ; Table giving addresses of jump vectors we need to update, along
          ; with offset from the start of the module to repoint those to.

patchseq:   dw    d_ideread, oldread, seqread
            dw    d_idewrite, oldwrite, seqwrite
            dw    d_idereset, null, parreset
            db    0

patchint:   dw    d_ideread, oldread, intread
            dw    d_idewrite, oldwrite, intwrite
            dw    d_idereset, null, parreset
            db    0


            org   ($ + 255) & 0ff00h

module:   ; Start the actual module code on a new page so that it forms
          ; a block of page-relocatable code that will be copied to himem.


seqread:    glo   r8
            ani   0f8h
            bnz   oorange

            glo   r8
            stxd
            ghi   r8
            stxd

            ani   01fh
            shl
            shl
            shl
            str   r2

            glo   r8
            or
            plo   r8

            ldi   0e0h
            phi   r8

            br    oldread


intread:    glo   r8
            ani   0f8h
            bnz   oorange

            glo   r8
            stxd
            ghi   r8
            stxd

            ani   01eh
            shl
            shl
            str   r2

            glo   r8
            or
            plo   r8

            ghi   r8
            ani   1
            ori   0e0h
            phi   r8

oldread:    sep   scall
            dw    d_ideread

return:     irx
            ldxa
            phi   r8
            ldx 
            plo   r8

parreset:   sep   sret


oorange:    smi   0
            sep   sret


seqwrite:   glo   r8
            ani   0f8h
            bnz   oorange

            glo   r8
            stxd
            ghi   r8
            stxd

            ani   01fh
            shl
            shl
            shl
            str   r2

            glo   r8
            or
            plo   r8

            ldi   0e0h
            phi   r8

            br    oldwrite


intwrite:   glo   r8
            ani   0f8h
            bnz   oorange

            glo   r8
            stxd
            ghi   r8
            stxd

            ani   01eh
            shl
            shl
            str   r2

            glo   r8
            or
            plo   r8

            ghi   r8
            ani   1
            ori   0e0h
            phi   r8

oldwrite:   sep   scall
            dw    d_idewrite

            br    return


          ; Module name for minfo to display

            db    0,'Parti',0


modend:   ; This is the last of what's copied to the heap.

end:      ; That's all folks!

