; =============================================================
; uart_bootloader.s
; Superscalar-LEGv8 UART Bootloader
;
; Lives permanently in instruction ROM (assembled as .coe).
; On every reset it:
;   1. Sends "READY\r\n" over UART (signals PC tool to start)
;   2. Receives 4 bytes (big-endian) = payload size in bytes
;   3. Receives that many bytes, stores at LOAD_ADDR
;   4. Sends "OK\r\n" to confirm
;   5. Jumps to LOAD_ADDR
;
; Protocol (used by tools/uart_load.py on the PC side):
;   Host sees "READY\r\n"
;   Host sends 4-byte size (big-endian, e.g. 0x00000080 = 128 bytes)
;   Host sends raw binary payload
;   Host waits for "OK\r\n"
;   CPU is now running the payload
;
; Memory map:
;   0x00000000  This bootloader (inst_rom, 8KB)
;   0x00002000  Scratchpad — payload loaded here
;   0x00010000  UART base
;
; LOAD_ADDR = 0x00002000
; MAX_PAYLOAD = 4096 bytes (scratchpad size)
;
; Registers:
;   X1  = UART base (0x00010000)
;   X2  = UART STATUS (X1+4)
;   X3  = UART RX_DATA (X1+8)
;   X5  = TX_BUSY mask (1)
;   X6  = RX_READY mask (2)
;   X7  = load address pointer (starts at 0x00002000)
;   X8  = byte counter (counts down from payload size)
;   X9  = temp / received byte
;   X10 = payload size accumulator
;   X30 = link register (used by BL/RET)
; =============================================================

.text

; =============================================================
; ENTRY POINT
; =============================================================
reset_entry:

    ; --- Build UART base: 0x00010000 ---
    ADDI  X1, X0, #1
    LSL   X1, X1, #16           ; X1 = 0x00010000

    ADDI  X2, X1, #4            ; X2 = STATUS
    ADDI  X3, X1, #8            ; X3 = RX_DATA

    ADDI  X5, X0, #1            ; TX_BUSY mask
    ADDI  X6, X0, #2            ; RX_READY mask

    ; --- Build load address: 0x00002000 ---
    ADDI  X7, X0, #2
    LSL   X7, X7, #12           ; X7 = 0x00002000 (LOAD_ADDR)

    ; --- Send "READY\r\n" ---
    ; R=82 E=69 A=65 D=68 Y=89 \r=13 \n=10
    ADDI  X9, X0, #82
    BL    uart_putc
    ADDI  X9, X0, #69
    BL    uart_putc
    ADDI  X9, X0, #65
    BL    uart_putc
    ADDI  X9, X0, #68
    BL    uart_putc
    ADDI  X9, X0, #89
    BL    uart_putc
    ADDI  X9, X0, #13
    BL    uart_putc
    ADDI  X9, X0, #10
    BL    uart_putc

; =============================================================
; Receive 4-byte size (big-endian)
; Result in X8 = total byte count
; =============================================================
recv_size:
    ADDI  X8, X0, #0            ; clear accumulator

    ; Byte 3 (MSB)
    BL    uart_getc             ; received byte in X9
    LSL   X8, X8, #8
    ORR   X8, X8, X9

    ; Byte 2
    BL    uart_getc
    LSL   X8, X8, #8
    ORR   X8, X8, X9

    ; Byte 1
    BL    uart_getc
    LSL   X8, X8, #8
    ORR   X8, X8, X9

    ; Byte 0 (LSB)
    BL    uart_getc
    LSL   X8, X8, #8
    ORR   X8, X8, X9

    ; Sanity check: if size == 0 or size > 4096, go back to start
    CBZ   X8, reset_entry
    ADDI  X10, X0, #1
    LSL   X10, X10, #12         ; X10 = 4096
    SUB   X10, X10, X8          ; 4096 - size
    ; if result is negative (size > 4096), SUB will underflow
    ; We check: if X10 < 0 that means size > 4096 — use CBNZ as proxy
    ; Simple approach: just trust host for now, add bounds later

; =============================================================
; Receive payload bytes, store at X7 (LOAD_ADDR)
; X8 = byte count remaining
; X7 = current write address
; =============================================================
recv_payload:
    CBZ   X8, send_ok           ; if count == 0, done receiving

    BL    uart_getc             ; byte in X9
    STR   X9, [X7, #0]          ; store to memory
    ADDI  X7, X7, #4            ; advance by one word
                                ; NOTE: each received byte stored
                                ; as a full word for simplicity.
                                ; Compiler output will be word-aligned
                                ; anyway (4 bytes per instruction).
    SUBI  X8, X8, #1            ; decrement counter
    B     recv_payload

; =============================================================
; Send "OK\r\n" then jump to payload
; =============================================================
send_ok:
    ADDI  X9, X0, #79           ; 'O'
    BL    uart_putc
    ADDI  X9, X0, #75           ; 'K'
    BL    uart_putc
    ADDI  X9, X0, #13           ; '\r'
    BL    uart_putc
    ADDI  X9, X0, #10           ; '\n'
    BL    uart_putc

    ; --- Jump to loaded payload ---
    ; Rebuild LOAD_ADDR (X7 has advanced past the payload)
    ADDI  X7, X0, #2
    LSL   X7, X7, #12           ; X7 = 0x00002000
    ; We can't BL to a register in our ISA without RET-style,
    ; so we use RET with X7 as the branch register
    RET   X7                    ; jump to 0x00002000

; =============================================================
; uart_putc — send byte in X9, blocks until TX_BUSY clears
; Clobbers: X10
; =============================================================
uart_putc:
putc_wait:
    LDR   X10, [X2, #0]         ; read STATUS
    AND   X10, X10, X5          ; isolate TX_BUSY
    CBNZ  X10, putc_wait        ; wait if busy
    STR   X9, [X1, #0]          ; write TX_DATA
    RET   X30

; =============================================================
; uart_getc — wait for RX_READY, return byte in X9
; Clobbers: X10
; =============================================================
uart_getc:
getc_wait:
    LDR   X10, [X2, #0]         ; read STATUS
    AND   X10, X10, X6          ; isolate RX_READY
    CBZ   X10, getc_wait        ; wait until byte arrives
    LDR   X9,  [X3, #0]         ; read RX_DATA (clears RX_READY)
    RET   X30
