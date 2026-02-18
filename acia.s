; vim:ts=4
; vim:sw=4

.setcpu "65C02"
.include "zeropage.inc65"
.include "io.inc65"
.include "macros.inc65"

ACIA_BUFFER_LENGTH = 10

.export acia_init
.export acia_getc
.export acia_gets
.export acia_putc
.export acia_puts
.export acia_put_newline
.export acia_puts_count

.code

;-------------------------------------------------------
; Initialise ACIA to 8N1 9600 baud
acia_init:
        pha
        ; 68B50 can do a SW reset
        lda #ACIA_RESET
        sta ACIA_CTRL_STATUS ; reset
        nop
        nop
        nop
        nop
        lda #0
        sta ACIA_CTRL_STATUS ; end reset sequence

        ; with external baud rate generator : RxCLK and TxCLK are 153600, giving DIV16=9600
        lda #(ACIA_8N1 | ACIA_CTRL_CR0)     ; Also RTS low, Tx Interrupt disabled
        sta ACIA_CTRL_STATUS
        pla
        rts
;-------------------------------------------------------


;-------------------------------------------------------
; Send the character in A
acia_putc:
        pha
wait_tdre1:
        ; wait for TDRE to be high
        lda ACIA_CTRL_STATUS
        and #ACIA_STATUS_TDRE
        beq wait_tdre1

        pla                     ; Get acc back
        sta ACIA_TX_RX          ; and write out
        rts
;-------------------------------------------------------

;-------------------------------------------------------
; Send the zero terminated string pointed to by R0
acia_puts:     
        pha
        phy
        ldy #$ff
next_char:
        iny
        lda (R0),y
        jsr acia_putc
        bne next_char
        ply
        pla
        rts
;-------------------------------------------------------

;-------------------------------------------------------
; Send the zero terminated string pointed to by R0
;  return count of chars printed in R1
acia_puts_count:
        pha
        phy
        ldy #$ff
apc_next_char:
        iny
        lda (R0),y
        jsr acia_putc
        bne apc_next_char
        STY R1            ; number of chars printed
        ply
        pla
        rts
;-------------------------------------------------------

;-------------------------------------------------------
; ACIA entry point
; Check physical KBD first then ACIA serial
;key_press:        CMP #$fe                      ; $FE = speial key (e.g Return or Backspace)
;                  BNE not_special
;                  ; decode of special keys here (e.g return, backspace) ...
not_special:      ;JSR acia_putc
;                  RTS
;-------------------------------------------------------
                  
;-------------------------------------------------------
; Wait until a character was reveiced on serial port and return it in A
acia_getc:         
wait_rxd_full:    
        lda ACIA_CTRL_STATUS 
        and #ACIA_STATUS_RDRF   ; Receiver Data Register Full
        beq wait_rxd_full       ; keep looping till receive
                                ; got something
        lda ACIA_TX_RX          ; get data
        rts
;-------------------------------------------------------


;-------------------------------------------------------
; Wait until a \n terminated string was received and store it at (R0)
; The accu contains the size of the buffer
; The \n is removed and the string is zero terminated
; After receiving buffer size - 1 characters, any following characters are discarded
acia_gets:        sta TMP0
                  phay
                  ldy #0
gets_next_char:   jsr acia_getc
                  ; Backspace
                  cmp #$08
                  beq backspace
                  ; CR
                  cmp #$0d
                  beq gets_eos
                  jsr acia_putc
                  cpy TMP0
                  beq gets_next_char
                  sta (R0),y
                  iny
                  jmp gets_next_char
backspace:        cpy #0
                  beq gets_next_char
                  dey
                  ; output ANSI "Cursor back"
                  lda #$1b
                  jsr acia_putc
                  lda #'['
                  jsr acia_putc
                  lda #'D'
                  jsr acia_putc
                  lda #$1b
                  jsr acia_putc
                  lda #'['
                  jsr acia_putc
                  lda #'K'
                  jsr acia_putc
                  jmp gets_next_char

gets_eos:         lda #0
                  sta (R0),y
                  jsr acia_put_newline
                  play
                  rts
;-------------------------------------------------------

;-------------------------------------------------------
; Send a newline character
acia_put_newline:
                  pha
                  lda #$0a
                  jsr acia_putc
                  lda #$0d
                  jsr acia_putc
                  pla
                  rts
;-------------------------------------------------------
                  
