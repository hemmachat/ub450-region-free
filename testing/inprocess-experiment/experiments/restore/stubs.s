@ ARM stubs for the restore experiment.
@ setgpr gains a magic register (0xf00) that runs the object scan instead of
@ writing. scan searches the writable ranges listed in the scratch block for
@ the JbiMiscAdapter vtable pointer, skipping addresses at or below the
@ "skip" word, and stores the object address plus its +0xc and +0x10 members
@ in GPR[3003..3005].

.syntax unified
.arm
.text

@ (target, reg, value); reg 0xf00 -> scan; reg 0xf01 -> read word;
@ GPR[reg] = value otherwise
.global setgpr_scan
setgpr_scan:
    cmp     r1, #0x1000
    bge     .Lfail
    cmp     r1, #0xf00
    beq     scan
    movw    r12, #0xf01
    cmp     r1, r12
    beq     readword
    ldr     r3, .Lg
    ldr     r3, [r3]
    sub     r3, r3, #0x4000
    str     r2, [r3, r1, lsl #2]
    mov     r0, #0
    bx      lr
.Lfail:
    mov     r0, #1
    bx      lr

@ scratch: +0 count, +4 target^mask, +8 skip, +0xc mask, +0x10 ranges
@ result: GPR[3003] = obj, GPR[3004] = [obj+0xc], GPR[3005] = [obj+0x10]
.global scan
scan:
    push    {r4-r10, lr}
    ldr     r4, .Lscratch
    ldr     r5, [r4]
    ldr     r6, [r4, #4]
    ldr     r0, [r4, #0xc]
    eor     r6, r6, r0
    ldr     r10, [r4, #8]
    ldr     r3, .Lg
    ldr     r3, [r3]
    sub     r3, r3, #0x4000
    mov     r2, #0
    add     r7, r4, #0x10
    mov     r8, #0
    b       .Louter
.Louter:
    cmp     r8, r5
    bge     .Ldone
    add     r9, r7, r8, lsl #3
    ldr     r1, [r9, #4]
    ldr     r9, [r9]
.Linner:
    cmp     r9, r1
    bge     .Lnext
    ldr     r0, [r9]
    cmp     r0, r6
    beq     .Lmatch
    add     r9, r9, #4
    b       .Linner
.Lmatch:
    cmp     r9, r10
    bls     .Lcont
    mov     r2, r9
    ldr     r0, [r9, #0xc]
    movw    r12, #0x2ef0
    str     r0, [r3, r12]
    ldr     r0, [r9, #0x10]
    movw    r12, #0x2ef4
    str     r0, [r3, r12]
    b       .Ldone
.Lcont:
    add     r9, r9, #4
    b       .Linner
.Lnext:
    add     r8, r8, #1
    b       .Louter
.Ldone:
    movw    r0, #0x2eec
    str     r2, [r3, r0]
    mov     r0, #0
    pop     {r4-r10, pc}

@ GPR[3011] = *(GPR[3010]); Java must check the address against the map
.global readword
readword:
    ldr     r3, .Lg
    ldr     r3, [r3]
    sub     r3, r3, #0x4000
    movw    r12, #0x2f08
    ldr     r2, [r3, r12]
    ldr     r2, [r2]
    movw    r12, #0x2f0c
    str     r2, [r3, r12]
    mov     r0, #0
    bx      lr

.align 2
.Lg:
    .word   0x010fc27c
.Lscratch:
    .word   0x11111111
