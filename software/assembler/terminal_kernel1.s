; ============================================================
; term_kernel.s — minimal kernel loop, prints to VGA, then spins
; ============================================================

        

main:
        ADDI X1, X0, #0x30000    
        ADDI X2, X0, msg         
        BL   puts                
        B    kernel_loop

; ------------------------------------------------------------
; kernel_loop — the OS. For now: no input source exists,
; so it just spins. This is the hook point for read_input later.
; ------------------------------------------------------------
kernel_loop:
        B    kernel_loop          ; TODO: BL read_input; dispatch on X0

; ------------------------------------------------------------
; putsX1 = vga cursor ptr, X2 = string ptr -> advances X1
; Clobbers: X3 char, X4 scratch
; ------------------------------------------------------------
puts:
puts_loop:
        LDR  X3, [X2, #0]        ; load next char (word-aligned string)
        CBZ  X3, puts_done       ; null terminator -> stop

        STR  X3, [X1, #0]        ; write char+color word to VGA cell
        ADDI X1, X1, #4          ; advance cursor one cell
        ADDI X2, X2, #4          ; advance string pointer one word
        B    puts_loop

puts_done:
        RET

; ------------------------------------------------------------
; String data — one ASCII char per 32-bit word, color = 0 (white),
; null-terminated. 31 characters + terminator.
; ------------------------------------------------------------
msg:
        .word 'S','u','p','e','r','s','c','a','l','a','r',' ','L','E','G','v','8',' ','K','e','r','n','e','l',' ','i','s',' ','O','N',0
