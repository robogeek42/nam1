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

; Initialize the ACIA
acia_init:        pha
                  lda #(ACIA_PARITY_DISABLE | ACIA_ECHO_DISABLE | ACIA_TX_INT_DISABLE_RTS_LOW | ACIA_RX_INT_DISABLE | ACIA_DTR_LOW)
                  sta ACIA_COMMAND
.ifdef FASTCPU
                  nop
                  nop
.endif
                  lda #(ACIA_STOP_BITS_1 | ACIA_DATA_BITS_8 | ACIA_CLOCK_INT | ACIA_BAUD_9600)
                  sta ACIA_CONTROL
.ifdef FASTCPU
                  nop
                  nop
.endif
				  pla
				  rts

; Send the character in A
acia_putc:        pha
wait_txd_empty:   lda ACIA_STATUS
                  and #ACIA_STATUS_TX_EMPTY
.ifdef FASTCPU
                  nop
                  nop
.endif
                  beq wait_txd_empty
                  pla
                  sta ACIA_DATA
                  rts

; Send the zero terminated string pointed to by R0
acia_puts:     
		  pha
		  phy
                  ldy #$ff
next_char:        iny
                  lda (R0),y
                  jsr acia_putc
                  bne next_char
		  ply
		  pla
                  rts
; Send the zero terminated string pointed to by R0
;  return count of chars printed in R1
acia_puts_count:
		  pha
		  phy
                  ldy #$ff
apc_next_char:    iny
                  lda (R0),y
                  jsr acia_putc
		  bne apc_next_char
                  STY R1            ; number of chars printed
		  ply
		  pla
                  rts

; ACIA entry point
; Check physical KBD first then ACIA serial
;key_press:        CMP #$fe                      ; $FE = speial key (e.g Return or Backspace)
;                  BNE not_special
;                  ; decode of special keys here (e.g return, backspace) ...
not_special:      ;JSR acia_putc
;                  RTS
                  
; Wait until a character was reveiced on serial port and return it in A
acia_getc:         
wait_rxd_full:    
                  lda ACIA_STATUS
.ifdef FASTCPU
                  nop
                  nop
.endif
                  and #ACIA_STATUS_RX_FULL
                  beq wait_rxd_full
                  lda ACIA_DATA
.ifdef FASTCPU
                  nop
.endif
                  rts

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

; Send a newline character
acia_put_newline: lda #$0a
                  jsr acia_putc
                  lda #$0d
                  jsr acia_putc
                  rts
                  
