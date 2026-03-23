; =============================================================
; hello_uart.s
; First baremetal program for Superscalar-LEGv8
;
; Memory map (locked):
;   0x00000000  Instruction ROM (this program loads here)
;   0x00002000  Data scratchpad
;   0x00010000  UART base address
;     +0x0      TX_DATA  (write: byte to send)
;     +0x4      STATUS   (read:  bit0=TX_BUSY, bit1=RX_READY)
;     +0x8      RX_DATA  (read:  received byte, clears RX_READY)
;
; Clock: 80MHz, Baud: 115200, Divisor: 694
;
; This program:
;   1. Sends "Hello, LEGv8!\r\n" over UART
;   2. Loops forever (blink-equivalent for a CPU with no LEDs yet)
;
; Registers used:
;   X1  = UART base address (0x00010000)
;   X2  = STATUS register address (X1 + 4)
;   X3  = current character pointer
;   X4  = current character value
;   X5  = TX_BUSY mask (0x1)
;   X6  = scratch / temp
;   X9  = data scratchpad base (0x00002000)
; =============================================================

.text

; -------------------------------------------------------------
; Entry point — CPU starts executing here at reset (PC=0)
; -------------------------------------------------------------
reset_entry:

    ; --- Set up UART base address in X1 ---
    ; 0x00010000 = 65536 decimal
    ; Build it: ADDI X1, X0, #1  then LSL X1, X1, #16
    ADDI  X1, X0, #1
    LSL   X1, X1, #16          ; X1 = 0x00010000 (UART base)

    ; STATUS register is at base + 4
    ADDI  X2, X1, #4            ; X2 = 0x00010004

    ; TX_BUSY mask
    ADDI  X5, X0, #1            ; X5 = 0x1 (TX_BUSY bit)

    ; --- Copy message into data scratchpad ---
    ; We store the string at scratchpad base 0x00002000
    ; then walk a pointer through it
    ADDI  X9, X0, #2            ; X9 = 2
    LSL   X9, X9, #12           ; X9 = 0x00002000 (scratchpad base)

    ; Store each character as a word (one per word address for simplicity)
    ; "Hello, LEGv8!\r\n" = 72 101 108 108 111 44 32 76 69 71 118 56 33 13 10 0
    ADDI  X6, X0, #72           ; 'H'
    STR   X6, [X9, #0]
    ADDI  X6, X0, #101          ; 'e'
    STR   X6, [X9, #4]
    ADDI  X6, X0, #108          ; 'l'
    STR   X6, [X9, #8]
    ADDI  X6, X0, #108          ; 'l'
    STR   X6, [X9, #12]
    ADDI  X6, X0, #111          ; 'o'
    STR   X6, [X9, #16]
    ADDI  X6, X0, #44           ; ','
    STR   X6, [X9, #20]
    ADDI  X6, X0, #32           ; ' '
    STR   X6, [X9, #24]
    ADDI  X6, X0, #76           ; 'L'
    STR   X6, [X9, #28]
    ADDI  X6, X0, #69           ; 'E'
    STR   X6, [X9, #32]
    ADDI  X6, X0, #71           ; 'G'
    STR   X6, [X9, #36]
    ADDI  X6, X0, #118          ; 'v'
    STR   X6, [X9, #40]
    ADDI  X6, X0, #56           ; '8'
    STR   X6, [X9, #44]
    ADDI  X6, X0, #33           ; '!'
    STR   X6, [X9, #48]
    ADDI  X6, X0, #13           ; '\r'
    STR   X6, [X9, #52]
    ADDI  X6, X0, #10           ; '\n'
    STR   X6, [X9, #56]
    ADDI  X6, X0, #0            ; null terminator
    STR   X6, [X9, #60]

    ; --- Set X3 = start of string (scratchpad base) ---
    ADDI  X3, X9, #0            ; X3 = string pointer

; -------------------------------------------------------------
; send_string: walk X3 through the string, send each byte
; -------------------------------------------------------------
send_string:
    LDR   X4, [X3, #0]          ; load current character
    CBZ   X4, done              ; if zero terminator, we're done

    ; --- wait_tx: spin until TX_BUSY == 0 ---
wait_tx:
    LDR   X6, [X2, #0]          ; read STATUS register
    AND   X6, X6, X5            ; isolate TX_BUSY bit
    CBNZ  X6, wait_tx           ; if busy, keep waiting

    ; --- send the character ---
    STR   X4, [X1, #0]          ; write to TX_DATA

    ; --- advance pointer by 4 (one word per char in our layout) ---
    ADDI  X3, X3, #4
    B     send_string

; -------------------------------------------------------------
; done: spin forever (halt equivalent)
; -------------------------------------------------------------
done:
    B     done
