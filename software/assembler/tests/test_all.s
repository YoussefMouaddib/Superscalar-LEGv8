; test_all.s — exercises every instruction in the ISA
; Expected to assemble without errors.
; Load address: 0x00000000

.text

; ============================================================
; R-type: register-register ALU
; ============================================================
start:
    ADD  X1, X2, X3         ; 0x00: R-type ADD  func=100000
    SUB  X4, X5, X6         ; 0x04: R-type SUB  func=100010
    AND  X7, X8, X9         ; 0x08: R-type AND  func=100100
    ORR  X10, X11, X12      ; 0x0C: R-type ORR  func=100101
    EOR  X13, X14, X15      ; 0x10: R-type EOR  func=100110
    NEG  X16, X17           ; 0x14: R-type NEG  func=101000
    CMP  X18, X19           ; 0x18: R-type CMP  func=101010

; ============================================================
; R-type: shifts
; ============================================================
    LSL  X20, X21, X22      ; 0x1C: reg shift,  func=000000
    LSR  X23, X24, X25      ; 0x20: reg shift,  func=000010
    LSL  X26, X27, #4       ; 0x24: imm shift,  func=000001, shamt=4
    LSR  X28, X29, #7       ; 0x28: imm shift,  func=000011, shamt=7

; ============================================================
; I-type: immediate ALU
; ============================================================
    ADDI X1, X2,  #100      ; 0x2C
    SUBI X3, X4,  #200      ; 0x30
    ANDI X5, X6,  #0xFF     ; 0x34
    ORI  X7, X8,  #0x0F     ; 0x38
    EORI X9, X10, #-1       ; 0x3C (all-ones mask)

; ============================================================
; D-type: load / store
; ============================================================
    LDR  X1,  [X2, #0]      ; 0x40
    LDR  X3,  [X4, #16]     ; 0x44
    STR  X5,  [X6, #-8]     ; 0x48
    LDUR X7,  [X8, #0]      ; 0x4C
    STUR X9,  [X10, #4]     ; 0x50

; ============================================================
; Atomic: CAS Xd, Xn, Xm
; ============================================================
    CAS  X1, X2, X3         ; 0x54

; ============================================================
; B-type: unconditional branch
; ============================================================
    B    after_b             ; 0x58 — forward branch
    NOP                      ; 0x5C — should be skipped
after_b:
    BL   subroutine          ; 0x60 — branch and link

; ============================================================
; CB-type: conditional branches
; ============================================================
    CBZ  X1, skip_z          ; 0x64
    ADDI X2, X2, #1          ; 0x68 — should be skipped
skip_z:
    CBNZ X3, not_zero        ; 0x6C
    NOP                      ; 0x70 — should be skipped
not_zero:

; ============================================================
; SYS
; ============================================================
    NOP                      ; 0x74 — all zeros
    SVC  #1                  ; 0x78 — syscall 1

; ============================================================
; RET
; ============================================================
    RET  X30                 ; 0x7C — return via X30 (LR)

; ============================================================
; Subroutine (called by BL above)
; ============================================================
subroutine:
    ADDI X0, X0, #42        ; 0x80
    RET                      ; 0x84 — implicit X30

; ============================================================
; .data section
; ============================================================
.data
data_word:
    .word 0xDEADBEEF
data_byte:
    .byte 0x42
.align 2                    ; align to 4 bytes
data_array:
    .word 1
    .word 2
    .word 3
    .word 4
