		.setcpu "65C02"
        .include "zeropage.inc65"
        .include "acia.inc65"
        .include "string.inc65"
        .include "macros.inc65"
        .include "io.inc65"

        .export print_memory16
        .export print_memory256

.bss
                BUFFER_LENGTH = 8
buffer:         .res BUFFER_LENGTH + 1, 0

.code

; Dump 16 bytes as hex and chars
;   address is in RES,RES+1
;   address to print is in R1,R1+1
print_memory16:  
				pha
				phy
                ; First print 4 char address
                ld16 R0, buffer
                lda R1 + 1
                jsr fmt_hex_string
                ld16 R0, buffer + 2
                lda R1
                jsr fmt_hex_string
                ld16 R0, buffer
                jsr acia_puts
                ; And then a space
                lda #' '
                jsr acia_putc
                jsr acia_putc

                ; print 16 bytes as hex
print_bytes:    ldy #0
                ld16 R0, buffer
next_byte:      lda (RES),y
                jsr fmt_hex_string
                jsr acia_puts
                lda #' '
                jsr acia_putc
                cpy #7
                bne @skip_mid_sep
                jsr acia_putc
@skip_mid_sep:  iny
                cpy #16
                bne next_byte

                ; print 16 bytes as chars
@print_chars:   lda #' '
                jsr acia_putc
                jsr acia_putc
                lda #'|'
                jsr acia_putc
                ldy #0
@next_char:     lda (RES),y
                ; anything less than ascii 32 is not printable
                cmp #$20
                bcc @non_printable
                cmp #$7e
                bcs @non_printable
                jmp @printable
@non_printable: lda #'.'
@printable:     jsr acia_putc
                iny
                cpy #16
                bne @next_char
                lda #'|'
                jsr acia_putc
                jsr acia_put_newline

;increment the address by 16
                clc
                lda RES
                adc #16
                sta RES
                lda RES + 1
                adc #0
                sta RES + 1
				ply
				pla
                rts

; dump a page. ZP_TMP0/1 has starting address
print_memory256:
				phaxy
				LDX #16
@pmloop:		LDA ZP_TMP0 
				STA RES
				STA R1
				LDA ZP_TMP0+1
				STA RES+1
				STA R1+1
				JSR print_memory16
				CLC
				LDA ZP_TMP0
				ADC #16
				STA ZP_TMP0
				LDA ZP_TMP0+1
				ADC #0
				STA ZP_TMP0+1
				DEX
				BNE @pmloop
				plaxy
				RTS
