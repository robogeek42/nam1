; vim: ts=4
.setcpu "65C02"

.include "zeropage.inc65"

.export BINBCD8
.export BINBCD16
.export BCD2STR
.export BCD4BYTE2STR

.code

;-----------------------------------------------------------------------
; Convert an 8 bit binary value to BCD
;
; This function converts an 8 bit binary value into a 16 bit BCD. It
; works by transferring one bit a time from the source and adding it
; into a BCD value that is being doubled on each iteration. As all the
; arithmetic is being done in BCD the result is a binary to decimal
; conversion.  All conversions take 311 clock cycles.
; Andrew Jacobs, 28-Feb-2004
BINBCD8:
		PHX
		STA BCD_IN
		SED			; Switch to decimal mode
		LDA #0		; Ensure the result is clear
		STA RES+0
		STA RES+1
		LDX #8		; The number of source bits

CNVBIT:
		ASL BCD_IN	; Shift out one bit
		LDA RES+0	; And add into result
		ADC RES+0
		STA RES+0
		LDA RES+1	; propagating any carry
		ADC RES+1
		STA RES+1
		DEX		; And repeat for next bit
		BNE CNVBIT
		CLD		; Back to binary
		
		PLX
		RTS		; All Done.
;-----------------------------------------------------------------------
; Assif - a 16 bit version of above
; Input in R1,R1+1 
; Output to TMP0,TMP0+1,TMP0+2 (TMP1+0)
; 2^16-1 = 65535 in BCD this needs 3 bytes (5 nibbles)
BINBCD16:
		PHX
        PHY
		SED			; Switch to decimal mode
		LDA #0		; Ensure the result is clear
		STA TMP0+0
		STA TMP0+1
		STA TMP0+2
		STA TMP0+3
        LDY #1      ; number of bytes in word
BB16_BYTELOOP:
        LDX #8		; The number of source bits in byte
        LDA R1,Y    ; start with MSB
        STA BCD_IN
BB16_BITLOOP:
		ASL BCD_IN	; Shift out one bit
		LDA TMP0+0	; And add into result
		ADC TMP0+0
		STA TMP0+0
		LDA TMP0+1	; propagating any carry
		ADC TMP0+1
		STA TMP0+1
        LDA TMP0+2	; propagating any carry to third byte
		ADC TMP0+2
		STA TMP0+2
        ;LDA TMP0+3	; and to fourth byte
		;ADC TMP0+3
		;STA TMP0+3
		DEX		    ; And repeat for next bit
		BNE BB16_BITLOOP
        DEY
        BPL BB16_BYTELOOP   ; for 1 & 0
		CLD		    ; Back to binary
		
        PLY
		PLX
		RTS		    ; All Done.
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Assif:
; Convert the BCD value in RES,RES+1 to string pointed to by R0
; ASCII 0 = $30 , no leading zeros
BCD2STR:
        pha
        phx
        phy
		LDY #0 					; point to pos in string
		LDX RES+1				; MSB
		CPX #0
		BNE b2s_do_msb			; not zero, so convert MSB
		LDX RES					; LSB
		CPX #0
		BNE b2s_do_lsb			; MSB is zero, only need to convert LSB
		LDA #'0'				; both are zero so
		STA (R0),Y				; write a zero
		INY
		JMP b2s_write_term_null	; and finish

b2s_do_msb:
		JSR b2s_read_byte		; MSB
b2s_do_lsb:
		LDX RES
		JSR b2s_read_byte		; LSB

b2s_write_term_null:
		LDA #0 					; finish with a terminating null
		STA (R0),Y
        ply
        plx
        pla
		RTS

;-----------------------------------------------------------------------
; subroutine to read a byte and write out digits
b2s_read_byte:
		TXA						; byte to convert in X
		LSR						; get top nibble
		LSR
		LSR
		LSR
		JSR b2s_write_digit		; write it
		TXA
		AND #$0F				; get bottom nibble
		JSR b2s_write_digit		; write it
		RTS

b2s_write_digit:
		CMP #0					; if digit is non-zero, print it
		BNE b2s_do_write_digit	
		CPY #0					; if digit is zero, but we have already printed something
		BNE b2s_do_write_digit	; then print it (a zero)
		RTS						; print nothing

b2s_do_write_digit:
		ORA #$30				; convert to ASCII
		STA (R0),Y				; write digit
		INY						; move write pointer
		RTS

;-----------------------------------------------------------------------
; Assif:
; Convert the BCD value in TMP0,TMP0+1,TMP0+3 to string pointed to by R0
; ASCII 0 = $30 , no leading zeros
BCD4BYTE2STR:
        pha
        phx
        phy
		LDY #0 					; point to pos in string

		LDX TMP0+2				; MMSB
		CPX #0
        BNE b4s_do_mmsb			; not zero, so convert all 3 bytes

		LDX TMP0+1				; MSB
		CPX #0
        BNE b4s_do_msb			; not zero, so convert MSB down

		LDX TMP0					; LSB
		CPX #0
		BNE b4s_do_lsb			; MSB is zero, only need to convert LSB

        LDA #'0'				; all bytes are zero so
		STA (R0),Y				; write a zero
		INY
		JMP b2s_write_term_null	; and finish

b4s_do_mmsb:
		JSR b2s_read_byte		; MSB
b4s_do_msb:
        LDX TMP0+1
		JSR b2s_read_byte		; MSB
b4s_do_lsb:
		LDX TMP0
		JSR b2s_read_byte		; LSB

        JMP b2s_write_term_null
