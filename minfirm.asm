.3ds
.create "min.firm",0
.headersize 0x0 + 0x3B00 ; ITCM, at offset where boot9 loads the firm header
                         ; Use the mirror at 0 so we can do PC-relative bl into the bootrom at 0xFFFFXXXX

payloadsector equ (0x0B400000 / 0x200)
nopslide_addr equ 0x1FFFA000 ; nop slide in AXIWRAM generated by a boot11 memset
nopslide_size equ 0x3C00
arm11stub_size equ (arm11stub_end - arm11stub)

area0maxsize equ (0x30 + 8) ; reserved + section 0 offset, address
area1maxsize equ (4 + 0x20 + 8) ; section 0 copy method + section 0 hash + section 1 offset, address
area2maxsize equ (4 + 0x20 + 8) ; section 1 copy method + section 1 hash + section 2 offset, address
area3maxsize equ (4 + 0x20 + 8) ; section 2 copy method + section 2 hash + section 3 offset, address
area4maxsize equ (4 + 0x20) ; section 3 copy method + section 3 hash

; Firm Header:
.area 0x10
.ascii "FIRM" ; magic
.word 0 ; boot priority
.word nopslide_addr | 1 ; arm11 entry
.word Entry | 1 ; arm9 entry
.endarea

.orga 0x10
area0:
.area area0maxsize

.skip 0x30 ; stupid known-plaintext XOR things. usually this could be used for code.

.thumb
Entry:
    add sp, #0x1FC ; place stack in unused ITCM, saves space over
                   ; using arm-mode code to put it in fcram or whatever

    add r0, =arm11stub
    ldr r1, =(nopslide_addr + nopslide_size)
    mov r2, #arm11stub_size

endarea0:
.endarea

.orga 0x48
.word 0 ; section 0 size

.orga 0x4C
area1:
.area area1maxsize

    blx 0xFFFF03F0 ; memcpy(src, dst, count)

    ; sdmmc stuff adapted from https://github.com/yellows8/unprotboot9_sdmmc
    ldr r1, =0xfff000b8
    mov r7, #1
    str r7, [r1]

    bl 0xffff1ff8 ; funcptr_boot9init

    bl 0xffff56c8 ; funcptr_mmcinit

    lsl r0, r7, #9
    add r0, #1 ; =0x201
    bl 0xffff5774 ; ub9_initdev

    ldr r2, =(nopslide_addr + nopslide_size)
    add r2, #(arm11stub_size + 4) ; load the FIRM header 4 bytes after the ARM11 stub
    mov r1, #1
    ldr r0, =payloadsector

    bl 0xffff55f8 ; ub9_readsectors(sector, size_sectors, address)

    ldr r6, =(nopslide_addr + nopslide_size)
    ldr r0, [r6, #(arm11stub_size + 4)] ; load magic from loaded FIRM header
    ldr r1, =0x4D524946 ; ascii "FIRM"

endarea1:
.endarea

.orga 0x78
.word 0 ; section 1 size

.orga 0x7C
area2:
.area area2maxsize

    cmp r0, r1
    bne arm9_write_reg_die ; if the FIRM magic doesn't match, die

    mov r4, #4
    add r6, #(0x40 + arm11stub_size + 4) ; point r6 to first FIRM section header

firmload_loop:
    ldmia r6!, {r0, r2, r3} ; load section offset, load address, size
    lsr r1, r3, #9 ; / 0x200 to get size in sectors
    beq firmload_skip ; if size is 0, don't do anything for this section
    lsr r0, #9 ; convert section offset to sectors
    ldr r3, =payloadsector
    add r0, r3
    bl 0xffff55f8 ; ub9_readsectors

firmload_skip:
    add r6, #0x24 ; advance r6 to point to the next section header
    sub r4, #1
    bne firmload_loop

    ldr r3, =(nopslide_addr + nopslide_size)
    ldr r4, [r3, #(0xC + arm11stub_size + 4)] ; load arm9 entrypoint from FIRM header

    str r3, [r3, #arm11stub_size] ; tell arm11 to jump to its entrypoint
                                  ; the specific value written here doesn't matter, just something > 1

    mov r0, #0 ; 0 out argc,
    mov r1, #0 ; argv, and
    mov r2, #0 ; magicWord (luma uses this for entrypoint detection)

    bx r4 ; jump to arm9 entrypoint

endarea2:
.endarea

.orga 0xA8
.word 0 ; section 2 size

.orga 0xAC
area3:
.area area3maxsize

arm9_write_reg_die:
    str r7, [r6, #arm11stub_size] ; tell arm11 to flash the power LED and die

arm9_die:
    b arm9_die

    ; more code can go here

.pool

endarea3:
.endarea

.orga 0xD8
.word 0 ; section 3 size

.orga 0xDC
area4:
.area area4maxsize

.thumb
.align 4
arm11stub: ; this all gets relocated to AXIWRAM and runs on arm11
    ldr r0, [arm11stub_end] ; this will always initially be 0;
                            ; arm9 will write here when it's time to do something
    cmp r0, #1 ; 0: loop, 1: set LED and die, else: jump to entrypoint
    blo arm11stub
    beq arm11stub_write_reg_die

    ldr r0, [arm11stub_end + 4 + 8] ; load arm11 entrypoint
    bx r0

arm11stub_write_reg_die:
    lsl r0, #29 ; =0x20000000
    mov sp, r0 ; place stack at the end of axiwram

    ldr r3, [boot11_i2c_write_reg]
    mov r0, #3
    mov r1, #0x29
    mov r2, #6
    blx r3 ; set power LED to flashing red

arm11stub_die:
    b arm11stub_die

.align 4
boot11_i2c_write_reg:
.word 0x000135CD
.align 4
arm11stub_end:

endarea4:
.endarea

.orga 0x100
.incbin "sig.bin"

.close

area0size equ (endarea0 - area0)
area1size equ (endarea1 - area1)
area2size equ (endarea2 - area2)
area3size equ (endarea3 - area3)
area4size equ (endarea4 - area4)

.notice "Area 0: 0x" + tohex(area0size, 2) + " / 0x" + tohex(area0maxsize, 2) + " bytes used, 0x" + tohex(area0maxsize - area0size, 2) + " bytes free"
.notice "Area 1: 0x" + tohex(area1size, 2) + " / 0x" + tohex(area1maxsize, 2) + " bytes used, 0x" + tohex(area1maxsize - area1size, 2) + " bytes free"
.notice "Area 2: 0x" + tohex(area2size, 2) + " / 0x" + tohex(area2maxsize, 2) + " bytes used, 0x" + tohex(area2maxsize - area2size, 2) + " bytes free"
.notice "Area 3: 0x" + tohex(area3size, 2) + " / 0x" + tohex(area3maxsize, 2) + " bytes used, 0x" + tohex(area3maxsize - area3size, 2) + " bytes free"
.notice "Area 4: 0x" + tohex(area4size, 2) + " / 0x" + tohex(area4maxsize, 2) + " bytes used, 0x" + tohex(area4maxsize - area4size, 2) + " bytes free"
.notice ""
.notice "Total: 0x" + tohex(area0size + area1size + area2size + area3size + area4size, 2) + " / 0x" + tohex(area0maxsize + area1maxsize + area2maxsize + area3maxsize + area4maxsize, 2) + " bytes used"