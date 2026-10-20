// SPDX-License-Identifier: GPL-3.0-or-later
// ARM64 Objective-C 2.0 message dispatch trampolines for Darling Embedded.

    .section __TEXT,__text,regular,pure_instructions
    .globl _objc_msgSend
    .p2align 2
_objc_msgSend:
    cbz     x0, Lnil_receiver
    stp     x29, x30, [sp, #-224]!
    mov     x29, sp
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    stp     x4, x5, [sp, #48]
    stp     x6, x7, [sp, #64]
    str     x8,     [sp, #80]
    stp     q0, q1, [sp, #96]
    stp     q2, q3, [sp, #128]
    stp     q4, q5, [sp, #160]
    stp     q6, q7, [sp, #192]

    bl      __objc_lookup_imp
    mov     x17, x0

    ldp     q6, q7, [sp, #192]
    ldp     q4, q5, [sp, #160]
    ldp     q2, q3, [sp, #128]
    ldp     q0, q1, [sp, #96]
    ldr     x8,     [sp, #80]
    ldp     x6, x7, [sp, #64]
    ldp     x4, x5, [sp, #48]
    ldp     x2, x3, [sp, #32]
    ldp     x0, x1, [sp, #16]
    ldp     x29, x30, [sp], #224

    cbz     x17, Lnil_receiver
    br      x17

    .globl _objc_msgSendSuper2
    .p2align 2
_objc_msgSendSuper2:
    cbz     x0, Lnil_receiver
    ldr     x9, [x0]
    cbz     x9, Lnil_receiver
    stp     x29, x30, [sp, #-224]!
    mov     x29, sp
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    stp     x4, x5, [sp, #48]
    stp     x6, x7, [sp, #64]
    str     x8,     [sp, #80]
    stp     q0, q1, [sp, #96]
    stp     q2, q3, [sp, #128]
    stp     q4, q5, [sp, #160]
    stp     q6, q7, [sp, #192]

    bl      __objc_lookup_super2_imp
    mov     x17, x0

    ldp     q6, q7, [sp, #192]
    ldp     q4, q5, [sp, #160]
    ldp     q2, q3, [sp, #128]
    ldp     q0, q1, [sp, #96]
    ldr     x8,     [sp, #80]
    ldp     x6, x7, [sp, #64]
    ldp     x4, x5, [sp, #48]
    ldp     x2, x3, [sp, #32]
    ldp     x0, x1, [sp, #16]
    ldp     x29, x30, [sp], #224

    ldr     x0, [x0]
    cbz     x17, Lnil_receiver
    br      x17

Lnil_receiver:
    mov     x0, #0
    mov     x1, #0
    movi    d0, #0
    movi    d1, #0
    movi    d2, #0
    movi    d3, #0
    ret

    .globl ___chkstk_darwin
    .p2align 2
___chkstk_darwin:
    ret

