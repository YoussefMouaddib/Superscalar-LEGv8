; ============================================================
; term_kernel.s — minimal kernel loop, prints to VGA, then spins
;
; Assemble:
;   ./legv8-as term_kernel.s -o term_kernel.coe -f coe --dump-symbols
; ============================================================

.text

main:
        ; VGA base: 0x00030000 = 3 << 16
        ADDI  X1, X0, #3
        ADDI  X27, X0, #16
        LSL   X1, X1, X27

        ; Load address of msg into X2
        ; Two-step: first assemble with --dump-symbols to find msg's address,
        ; then replace the 0 below with that value.
        ; If msg address > 32767 you need: ADDI X2, X0, #hi; LSL; ORI X2, X2, #lo
        ADDI  X2, X0, #0          ; REPLACE with msg byte address from symbols

        BL    puts

kernel_loop:
        B     kernel_loop

; ------------------------------------------------------------
; puts: X1=VGA cursor, X2=string ptr. Clobbers X3.
; ------------------------------------------------------------
puts:
puts_loop:
        LDR   X3, [X2, #0]
        CBZ   X3, puts_done
        STR   X3, [X1, #0]
        ADDI  X1, X1, #4
        ADDI  X2, X2, #4
        B     puts_loop
puts_done:
        RET   X30

; ------------------------------------------------------------
; msg: "Superscalar LEGv8 Kernel is ON" — one word per char
; ------------------------------------------------------------
msg:
        .word 0x53
        .word 0x75
        .word 0x70
        .word 0x65
        .word 0x72
        .word 0x73
        .word 0x63
        .word 0x61
        .word 0x6C
        .word 0x61
        .word 0x72
        .word 0x20
        .word 0x4C
        .word 0x45
        .word 0x47
        .word 0x76
        .word 0x38
        .word 0x20
        .word 0x4B
        .word 0x65
        .word 0x72
        .word 0x6E
        .word 0x65
        .word 0x6C
        .word 0x20
        .word 0x69
        .word 0x73
        .word 0x20
        .word 0x4F
        .word 0x4E
        .word 0
