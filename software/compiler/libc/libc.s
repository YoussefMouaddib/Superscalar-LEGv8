; =============================================================
; libc.s — Minimal C runtime for Superscalar-LEGv8
;
; ABI (locked):
;   X0-X5   args, X0 return value
;   X28     SP (grows down)
;   X29     FP
;   X30     LR
;   X27     compiler scratch (shift amounts)
;
; Memory map:
;   0x00010000  UART TX_DATA  (write: byte to send)
;   0x00010004  UART STATUS   (bit0=TX_BUSY, bit1=RX_READY)
;   0x00010008  UART RX_DATA  (read: received byte, clears RX_READY)
;
; Calling convention for all functions here: standard ABI above.
; All leaf functions only use X0-X15 (caller-saved) unless noted.
; =============================================================

.text

; =============================================================
; __runtime_init — call before main()
; Sets up SP = 0x00002FFC (top of 4KB scratchpad)
; =============================================================
__runtime_init:
    ADDI  X0, X0, #2          ; X0 = 2
    LSL   X0, X0, X27         ; need X27 = 12 for this... better:
    ; Build 0x00002FFC:
    ;   0x00002FFC = 0x3000 - 4 = (3 << 12) - 4
    ADDI  X0, X0, #3          ; X0 = 3
    ADDI  X27, X0, #12        ; X27 = 12 (shift amount)
    LSL   X0, X0, X27         ; X0 = 3 << 12 = 0x3000
    SUBI  X0, X0, #4          ; X0 = 0x2FFC
    ORR   X28, X0, X0         ; SP = 0x2FFC
    ; Build UART base: 0x00010000 = 1 << 16
    ADDI  X0, X0, #1          ; X0 = 1
    ADDI  X27, X0, #16        ; X27 = 16
    LSL   X0, X0, X27         ; X0 = 0x00010000
    ; (UART base not stored here — each function builds it locally)
    RET   X30

; =============================================================
; uart_putc(int c) — send byte in X0 over UART, poll TX_BUSY
; Clobbers: X1, X2, X3
; =============================================================
uart_putc:
    ; Build UART base in X1
    ADDI  X1, X0, #1
    ADDI  X27, X0, #16
    LSL   X1, X1, X27         ; X1 = 0x00010000
    ORR   X3, X0, X0          ; X3 = char to send (save X0)
    ADDI  X2, X1, #4          ; X2 = STATUS reg
    ADDI  X0, X0, #1          ; X0 = TX_BUSY mask
.Lputc_wait:
    LDR   X27, [X2, #0]       ; read STATUS
    AND   X27, X27, X0        ; isolate TX_BUSY
    CBNZ  X27, .Lputc_wait
    STR   X3, [X1, #0]        ; write to TX_DATA
    RET   X30

; =============================================================
; uart_getc() → int — wait for byte, return in X0
; Clobbers: X1, X2, X3
; =============================================================
uart_getc:
    ADDI  X1, X0, #1
    ADDI  X27, X0, #16
    LSL   X1, X1, X27         ; X1 = 0x00010000
    ADDI  X2, X1, #4          ; X2 = STATUS
    ADDI  X3, X1, #8          ; X3 = RX_DATA
    ADDI  X0, X0, #2          ; X0 = RX_READY mask
.Lgetc_wait:
    LDR   X27, [X2, #0]
    AND   X27, X27, X0
    CBZ   X27, .Lgetc_wait
    LDR   X0, [X3, #0]        ; read byte (clears RX_READY)
    RET   X30

; =============================================================
; putchar(int c) → int — send c to UART, return c
; =============================================================
putchar:
    ORR   X16, X0, X0         ; save c
    BL    uart_putc
    ORR   X0, X16, X0         ; return c
    RET   X30

; =============================================================
; puts(int *s) — print null-terminated string + newline
; X0 = pointer to string in memory (word per char layout)
; =============================================================
puts:
    ORR   X16, X0, X0         ; X16 = string pointer
.Lputs_loop:
    LDR   X0, [X16, #0]       ; load current char
    CBZ   X0, .Lputs_nl       ; null terminator → print newline
    BL    uart_putc
    ADDI  X16, X16, #4        ; advance by one word
    B     .Lputs_loop
.Lputs_nl:
    ADDI  X0, X0, #10         ; '\n'
    BL    uart_putc
    ADDI  X0, X0, #0          ; return 0
    RET   X30

; =============================================================
; memcpy(int *dst, int *src, int n) — copy n WORDS (not bytes)
; Returns dst (X0)
; X0=dst, X1=src, X2=n
; =============================================================
memcpy:
    ORR   X16, X0, X0         ; X16 = dst (save for return)
    CBZ   X2, .Lmemcpy_done
.Lmemcpy_loop:
    LDR   X17, [X1, #0]       ; load word from src
    STR   X17, [X0, #0]       ; store word to dst
    ADDI  X0, X0, #4
    ADDI  X1, X1, #4
    SUBI  X2, X2, #1
    CBNZ  X2, .Lmemcpy_loop
.Lmemcpy_done:
    ORR   X0, X16, X0         ; return original dst
    RET   X30

; =============================================================
; memset(int *dst, int val, int n) — fill n WORDS with val
; Returns dst (X0)
; X0=dst, X1=val, X2=n
; =============================================================
memset:
    ORR   X16, X0, X0         ; save dst
    CBZ   X2, .Lmemset_done
.Lmemset_loop:
    STR   X1, [X0, #0]
    ADDI  X0, X0, #4
    SUBI  X2, X2, #1
    CBNZ  X2, .Lmemset_loop
.Lmemset_done:
    ORR   X0, X16, X0
    RET   X30

; =============================================================
; strlen(int *s) → int — count words until null word
; X0 = pointer to string (word per char layout)
; =============================================================
strlen:
    ORR   X16, X0, X0         ; X16 = ptr
    ADDI  X17, X0, #0         ; X17 = count = 0
.Lstrlen_loop:
    LDR   X0, [X16, #0]
    CBZ   X0, .Lstrlen_done
    ADDI  X17, X17, #1
    ADDI  X16, X16, #4
    B     .Lstrlen_loop
.Lstrlen_done:
    ORR   X0, X17, X0         ; return count
    RET   X30

; =============================================================
; print_int(int n) — print decimal integer over UART
; X0 = integer to print (treated as unsigned for simplicity)
; Uses scratchpad at 0x00002F00 as digit buffer (top of scratch)
; =============================================================
print_int:
    ; Handle negative numbers
    ORR   X16, X0, X0         ; X16 = n
    CBZ   X16, .Lpi_zero
    ADDI  X17, X0, #0         ; X17 = 0 (sign check via MSB)
    ADDI  X27, X0, #31
    LSR   X17, X16, X27       ; X17 = sign bit
    CBZ   X17, .Lpi_positive
    ; Negative: print '-', negate
    ADDI  X0, X0, #45         ; '-'
    BL    uart_putc
    NEG   X16, X16

.Lpi_positive:
    ; Build digit buffer at scratch+0xF00 = 0x00002F00
    ; (well below our SP at 0x2FFC — safe)
    ADDI  X0, X0, #2
    ADDI  X27, X0, #12
    LSL   X0, X0, X27         ; X0 = 0x2000
    ADDI  X0, X0, #0xF00      ; X0 = 0x2F00  ← digit buffer base
    ; Hmm — 0xF00 = 3840 fits in imm16 ✓
    ORR   X18, X0, X0         ; X18 = buf pointer
    ADDI  X17, X0, #0         ; X17 = digit count

    ; Divide by 10 repeatedly using shift-and-subtract
    ; (no divide instruction — use software division)
    ORR   X0, X16, X0         ; X0 = n
.Lpi_extract:
    ; digit = n % 10, n = n / 10
    BL    __udiv10             ; X0=quotient, X1=remainder
    ADDI  X1, X1, #48         ; ASCII digit
    STR   X1, [X18, #0]
    ADDI  X18, X18, #4
    ADDI  X17, X17, #1
    CBNZ  X0, .Lpi_extract

    ; Digits are in reverse order — print backwards
    SUBI  X18, X18, #4        ; point to last digit
.Lpi_print:
    LDR   X0, [X18, #0]
    BL    uart_putc
    SUBI  X18, X18, #4
    SUBI  X17, X17, #1
    CBNZ  X17, .Lpi_print
    RET   X30

.Lpi_zero:
    ADDI  X0, X0, #48         ; '0'
    BL    uart_putc
    RET   X30

; =============================================================
; __udiv10(int n) → X0=quotient, X1=remainder
; Software unsigned divide by 10 using shift-subtract
; X0 = dividend
; =============================================================
__udiv10:
    ORR   X16, X0, X0         ; X16 = dividend
    ADDI  X0, X0, #0          ; X0 = quotient = 0
    ADDI  X17, X0, #10        ; X17 = divisor = 10
    ; Find highest bit position of divisor relative to dividend
    ; Simple long division: shift divisor left until > dividend,
    ; then shift right and subtract when possible
    ADDI  X18, X0, #0         ; X18 = shift count
.Ludiv_align:
    ; Check if divisor * 2 <= dividend
    ADDI  X27, X0, #1
    LSL   X27, X17, X27       ; X27 = divisor << 1
    ; if X27 > X16 stop
    SUB   X27, X27, X16       ; X27 = (div<<1) - dividend
    ADDI  X27, X27, #0        ; just use sign bit check
    ADDI  X27, X0, #31
    LSR   X27, X27, X27       ; sign bit of ((div<<1)-dividend)
    CBZ   X27, .Ludiv_shift_done  ; if >= 0: (div<<1) >= dividend, stop
    ADDI  X27, X0, #1
    LSL   X17, X17, X27       ; divisor <<= 1
    ADDI  X18, X18, #1
    B     .Ludiv_align
.Ludiv_shift_done:
    ; Now long-divide
.Ludiv_loop:
    SUB   X27, X16, X17       ; X27 = dividend - divisor
    ADDI  X27, X27, #0
    ADDI  X27, X0, #31
    LSR   X27, X27, X27       ; sign bit
    CBNZ  X27, .Ludiv_no_sub  ; if negative: can't subtract
    ORR   X16, X27, X0        ; dividend -= divisor
    SUB   X16, X16, X17
    ; set bit in quotient
    ADDI  X27, X0, #1
    LSL   X27, X27, X18       ; 1 << shift_count
    ORR   X0, X0, X27         ; quotient |= bit
.Ludiv_no_sub:
    CBZ   X18, .Ludiv_done
    SUBI  X18, X18, #1
    ADDI  X27, X0, #1
    LSR   X17, X17, X27       ; divisor >>= 1
    B     .Ludiv_loop
.Ludiv_done:
    ORR   X1, X16, X0         ; X1 = remainder
    RET   X30

; =============================================================
; __start — entry point wrapper
; Sets up runtime and calls main()
; Place this at address 0x00000000 (start of inst_rom)
; =============================================================
__start:
    BL    __runtime_init
    BL    main
    ; main returned in X0 — loop forever (halt)
.Lhalt:
    B     .Lhalt
