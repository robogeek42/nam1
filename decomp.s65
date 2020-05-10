; vim: ts=8
.setcpu "65C02"

.include "zeropage.inc65"
.include "macros.inc65"
.include "video_registers.inc65"
.include "video_common.inc65"
.include "video.inc65"
.include "acia.inc65"
.include "sd.inc65"
.include "string.inc65"

.export decompRLE1_SC2

.code

msg_bad_header: .byte "bad header",$00
msg_header: .byte "header ",$00

; Decompress an SC2 image in my RLE compressed file format
; Blocks: PT_BLK0-2, CT_BLK0-2
; Header: RLE1 + Size (lsb.msb)
; Encoding: 1st char = run length. b7=same or differnt chars
;
; Pass address of data in TMP1
decompRLE1_SC2:
		phy
		phx
		
		LDX#3							; 3 blocks of pattern table pages
		JSR vdp_setaddr_pattern_table	

dr1_next_PT_block:
		JSR dr1_read_header				; get size into TMP2
		BCS dr1_exit					; bad header
		add8To16 #6, TMP1				; move ptr to start of data
		JSR dr1_write_block				; will also move TMP1 to after the data
		DEX
		BNE dr1_next_PT_block			

		LDX#3							; 3 blocks of colour table pages
		JSR vdp_setaddr_color_table_g2

dr1_next_CT_block:
		JSR dr1_read_header				; get size into TMP2
		BCS dr1_exit					; bad header
		add8To16 #6, TMP1				; move ptr to start of data
		JSR dr1_write_block				; will also move TMP1 to after the data
		DEX
		BNE dr1_next_CT_block			
		
		;; load name table to consective names
		JSR vdp_load_number_name_table
		JMP dr1_good_exit

dr1_exit:
		ld16 R0, msg_bad_header
		JSR acia_puts
		JSR acia_put_newline
dr1_good_exit:
		plx
		ply
		RTS

;---------------------------------------------------------
; Read char from either address at (TMP1),Y or the SD card
rl1_get_char:
		LDA OUT_LIST_SD
		BNE read_from_sd
		LDA (TMP1),Y
		RTS
read_from_sd:
.ifdef SDIO
		JSR fs_get_next_byte
		BCS read_eof		; C=1 means EOF reached

        PHA
        PLA
		RTS
read_eof:
		ld16 R0, msg_EOF
		JSR acia_puts
		JSR acia_put_newline
		LDA #0
.else
		LDA (TMP1),Y
.endif
		RTS

;---------------------------------------------------------
; read header from address in TMP1, put size in TMP2
; returns C=1 if failed
rle1_header:
.byte 'R','L','E',$01
dr1_read_header:
		LDY #0
@loop1:
		;LDA (TMP1),Y
		JSR rl1_get_char
		CMP	rle1_header,Y
		BNE dr1_bad_file_header
		INY
		CPY #4
		BNE @loop1
		;LDA (TMP1),Y	; LSB of size
		JSR rl1_get_char
		STA TMP2
		INY
		;LDA (TMP1),Y	; MSB of size
		JSR rl1_get_char
		STA TMP2+1

		ld16 R0, msg_header
		JSR acia_puts
		JSR acia_put_newline

		CLC
		RTS

dr1_bad_file_header:
		SEC
		RTS


; Read a compressed block and write to VDP
; Size is in TMP2, Address in TMP1
dr1_write_block:
		; repeat 
		; 	read control byte. control AND 7F => count (--Size)
		; 	if control < $80 do "repeat" else do "unique"
		; 	"repeat": read char (--Size). write char count times
		; 	"unique": write next count chars directly (Size-=count)
		; until Size==0
		phx
        LDA #16
		LDY #0						; Y is never incremented
dr1_loop_main:
		;LDA (TMP1),Y				; zero-page indirect (Y==0)
		JSR rl1_get_char
		BMI dr1_unique_chars
		; repeat char
		TAX							; put the count in X

		JSR dr1_dec_size			; decrement size
		BCC dr1_wb_done			

		INC TMP1
		BNE @over1
		INC TMP1+1
@over1:

		;LDA (TMP1),Y				; load the char to write
		JSR rl1_get_char
dr1_loop_rc:
		JSR vdp_write
		DEX							; X times
		BNE dr1_loop_rc

		JSR dr1_dec_size			; decrement size
		BCC dr1_wb_done

		INC TMP1
		BNE @over2
		INC TMP1+1
@over2:

		JMP dr1_loop_main				; go get next ctrl char

dr1_unique_chars:
		AND #$7F
		TAX							; put the count in X
dr1_loop_uc:
		JSR dr1_dec_size			; decrement size
		BCC dr1_wb_done			

		INC TMP1
		BNE @over3
		INC TMP1+1
@over3:

		;LDA (TMP1),Y				; load the char to write
		JSR rl1_get_char
        JSR vdp_write				; write char
		DEX							; X times
		BNE dr1_loop_uc
		; done uc loop
		
		JSR dr1_dec_size			; decrement size
		BCC dr1_wb_done

		INC TMP1
		BNE @over4
		INC TMP1+1
@over4:

		JMP dr1_loop_main				; go get next ctrl char


dr1_wb_done:
		INC TMP1
		BNE @over5
		INC TMP1+1
@over5:
		plx
		RTS

; decrement size and return CLC if 0
dr1_dec_size:
		dec16 TMP2
		LDA TMP2+1
		BNE @not_zero
		LDA TMP2
		BNE @not_zero
		CLC
		RTS
@not_zero:
		SEC
		RTS

