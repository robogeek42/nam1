; vim: ts=4
; TMS9918A/9929A Video Control
;
		.setcpu "65C02"
		.include "zeropage.inc65"
		.include "acia.inc65"
		.include "string.inc65"
		.include "macros.inc65"
		.include "io.inc65"
		.include "video_registers.inc65"
		.include "video_common.inc65"
		.include "video_chartable_1.inc65"
		.include "sprite.inc65"
		.include "print_util.inc65"

		.export vdp_dump_page
		.export vdp_set_mode
		.export vdp_clear_screen
		.export vdp_load_chars
		.export vdp_load_g1_col
		.export vdp_set_pos
		.export vdp_write_char
		.export vdp_write_text
		.export vdp_backspace
		.export vdp_load_flat_colors
		.export vdp_set_base_colors
		.export vdp_load_number_name_table
		.export vdp_load_mc_standard_name_table
		.export vdp_copy
		.export vdp_cursor_on
		.export vdp_cursor_off
		; copy cursor
		.export vdp_cc_enable
		.export vdp_cc_disable
		.export vdp_cc_read
		.export vdp_cc_write
		.export vdp_cc_on
		.export vdp_cc_off
		.export vdp_cc_move_up
		.export vdp_cc_move_down
		.export vdp_cc_move_left
		.export vdp_cc_move_right


.bss
page_buffer:	.res 256, 0

.code
.include "vdp_mem_map.inc65"

;================================================================
; VDP Set Mode - mode passed in Acc
vdp_set_mode:	STA VDP_MODE
				ASL ; Multiply Acc by 8 to give offset into mode reg table
				ASL 
				ASL
				STA TMP0
				CLC 
				ld16 ZP_TMP0, VDP_MODES ; store address of mode table in ZP_TMP0/1
				LDA TMP0				; 8 * mode #
				ADC ZP_TMP0				; add 8*mode to mode base to point to this modes settings
				STA ZP_TMP0
				LDA #0
				ADC ZP_TMP0+1
				STA ZP_TMP0+1

				LDX #$80
				LDY #0
vdp_sm_loop:	LDA (ZP_TMP0), Y		; Load register value from mode tab
				STA VDP_REGS,Y			; Save it in zero page
				STA VDP_WR_REG			; set registers directly as subroutine uses X for reg num
.ifdef FASTCPU
				NOP
				NOP
				NOP
.endif
				STX VDP_WR_REG
.ifdef FASTCPU
				NOP
				NOP
				NOP
.endif
				INY
				INX
				CPY #8
				BNE vdp_sm_loop

				LDA #0
				STA ZP_CURSOR

				;; set some mode specific vars
				LDA VDP_MODE
				CMP #0
				BEQ vdp_sm_text_mode
				LDA #32
				STA VDP_CHAR_WIDTH

				;; Load char-set, colours and clear screen
				JSR vdp_load_chars  
				LDA VDP_REGS+7
				JSR vdp_load_flat_colors
				JSR vdp_clear_screen

				;; store the sprite table address
				;; it will be frequently used and is slow to derive
				;; SAB = REG5 * 0x80 (makes upper 7 bits of 14 bit address)
				LDA VDP_REGS+5	
				CLC				 
				ROR A				
				STA VDP_SAB+1	;; put shifted right bits into hi word
				LDA #0
				ROR A				;; and lsbit into top bit of low word of address
				STA VDP_SAB

				JSR vdp_init_sprites

				RTS

vdp_sm_text_mode: 
				LDA #40
				STA VDP_CHAR_WIDTH
				JSR vdp_load_chars  
				JSR vdp_clear_screen
				RTS

;================================================================
; Load Character Table subroutine
; Has maximum of 256 chars * 8 bytes (2k)
; To make character name = ASCII value, load by ASCII code
; so Space ($20) loads into address BASE+$20*8 
;
vdp_load_chars: 
				LDA VDP_MODE
				CMP #3
				BEQ vlc_done

				;; pattern table
				JSR vdp_setaddr_pattern_table
				JSR vlc_load
				LDA VDP_MODE
				CMP #2
				BNE vlc_done

; mode 2 - load chars twice more
				LDA #$08
				STA TMP0
				JSR vdp_setaddr_pattern_table_offset
				JSR vlc_load

				LDA #$10
				STA TMP0
				JSR vdp_setaddr_pattern_table_offset
				JSR vlc_load

vlc_done:		RTS

vlc_load:		ld16 TMP0,CHAR_TAB  ;; character defs
				LDX #04				;; write 4 blocks of 256
				LDY #00
lc_loop1:		LDA (TMP0),Y
				JSR vdp_write
				INY
				BNE lc_loop1
				INC TMP0+1		  ;; inc char addr by 256
				DEX
				BNE lc_loop1

				; Write inverse in second 128 chars
				ld16 TMP0,CHAR_TAB  ;; character defs
				LDX #04				;; write 4 blocks of 256
				LDY #00
lc_loop2:		LDA (TMP0),Y
				EOR #$FF
				JSR vdp_write
				INY
				BNE lc_loop2
				INC TMP0+1		  ;; inc char addr by 256
				DEX
				BNE lc_loop2
				
				RTS
;----------------------------------------------------------------

;================================================================
; Load color table - only for modes 1 & 2
;	- colour is in Accumulator
vdp_load_flat_colors:
				LDX VDP_MODE
				CPX #1
				BEQ vdp_load_g1_col
				CPX #2
				BEQ vdp_load_g2_col
				RTS

; Load Color Table for Graphics Mode I characters
; 1 color (byte) per 8 chars in CHAR_TABLE (32 bytes for 256 chars)
; Col encoded in a byte MSNib foreground LSNib background
;
vdp_load_g1_col: 
				PHA				;; color in Acc
				LDA VDP_REGS+3	;; Set VRAM address to VDP_REG3 * 0x40
				STA ZP_TMP0
				LDX #0
				STX ZP_TMP0+1
lgc_loop1:		ASL ZP_TMP0
				ROL ZP_TMP0+1
				INX
				CPX #6
				BNE lgc_loop1
				LDY ZP_TMP0
				LDA ZP_TMP0+1
				JSR vdp_set_addr_w

				PLA					;; color
				LDY #$00			
lgc_loop:		JSR vdp_write
				INY
				CPY #$20			;; 32 entries
				BNE lgc_loop
				RTS
;----------------------------------------------------------------

;================================================================
; Load Color Table for Graphics Mode II characters
; 8 colors per 8 bytes (i.e per character) - sections like pattern table
;
vdp_load_g2_col:
				PHA					;; color in Acc
				LDA VDP_REGS+3		;; Color table
				AND #$80			;; just want upper bit
				CLC
				ROR
				ROR
				LDY #0
				JSR vdp_set_addr_w
				
				PLA
				LDX #24			 ;; 24*256=3*2k
lgc2_loop_outer:
				LDY #00
lgc2_loop:	  JSR vdp_write
				INY
				BNE lgc2_loop
				DEX
				BNE lgc2_loop_outer
				RTS


;================================================================
; Set base colors (VDP reg 7) 
vdp_set_base_colors:
				STA TMP0
				phx
				phy
				; save color in ZP regs
				STA VDP_REGS+7
				; set BG/FG Col
				LDY #$87
				JSR vdp_regwrite	;; write value of Acc to Reg 7 (Col)
				LDA VDP_MODE
				BEQ @done_set_base_cols	; Mode 0 we are done
				LDA TMP0
				JSR vdp_load_flat_colors
@done_set_base_cols: 
				LDA TMP0
				ply
				plx
				RTS
;----------------------------------------------------------------

;================================================================
; Clear screen
; clear by writing a space char ($20) to all name space entries
vdp_clear_screen: 
				LDA VDP_MODE
				CMP #3
				BEQ cs_clear_multicolor

				LDY #00			 ;; Set VRAM address to VDP_REG2 * 0x400
				LDA VDP_REGS+2
				ASL
				ASL
				JSR vdp_set_addr_w
				
;  write ASCII $20 to screen
cs_write_spaces:
				LDA #$20				
				LDY #24				 ; Screens are 24 chars high
cs_loop_row:	LDX VDP_CHAR_WIDTH	; and either 32 or 40 wide
cs_loop_col:	JSR vdp_write
				DEX
				BNE cs_loop_col
				DEY
				BNE cs_loop_row

cs_reset_cursor:
				LDA #0				  ; reset cursor pos
				STA VDP_CURS
				STA VDP_CURS+1
				STA VDP_XPOS
				STA VDP_YPOS
				RTS

cs_clear_multicolor:
				;; set name table to consecutive patterns
				JSR vdp_load_number_name_table

				;; set pattern table to black
				JSR vdp_setaddr_pattern_table
				LDX #8
				LDY #0
				LDA #0
cs_loop1:		JSR vdp_write
				INY
				BNE cs_loop1
				DEX
				BNE cs_loop1
				JMP cs_reset_cursor
;----------------------------------------------------------------

;================================================================
; Dump VRAM page 
;   destroys Y
;   Input : ZP_TMP0 = page to read
;   Output : prints to console
;   Uses : (ZP) RES  - address of page buffer
;          (ZP) R1
;   Calls : print_memory16
;           Input : (ZP) RES memory location to read data from
;                   (ZP) R1 (address to print)
;           Uses  : (ZP) R0 
;           Calls : fmt_hex_string
;                   Input : Acc
;                         : R0
;                   Uses : TMP0
vdp_dump_page:
				; read back to CPU memory
				ld16 RES, page_buffer	;; set read-back address
				LDY #0					;; set VDP VRAM read address (and test 256 bytes)
				LDA ZP_TMP0				;; page
				JSR vdp_set_addr_r
vt1_loop1:	  JSR vdp_read				;; read back
				STA (RES),Y
				INY
				BNE vt1_loop1

				; print out the page
				LDX #$10				;; 16*16 bytes
				; R1 will contain the VDP page address (not buffer address)
				LDA ZP_TMP0 
				STA R1+1
				LDA #0
				STA R1
vt1_loop2:	  JSR print_memory16		;; print 16 bytes from (RES) and inc RES by 16
				; increment the VDP age address
	vt1_add16:
				CLC
				LDA #16
				ADC R1
				STA R1
				LDA #0
				ADC R1+1
				STA R1+1
				DEX
				BNE vt1_loop2
				RTS

;================================================================
; Write char and string

; Setup a VDP write to VDP_CURS (2byte) position
vdp_start_str_w:
				phay
				LDA VDP_REGS+2		;; Load Name tab from Reg2
				ASL					;; NameTab Addr = reg2 * 0x400
				ASL
				CLC
				ADC VDP_CURS+1	;; add curs hi byte to screen hi (res in A)
				LDY VDP_CURS		;; add curs lo byte to screen lo (0)
				JSR vdp_set_addr_w  
				play
				RTS

;------------------------------------------------
; Set screen position.
; Start VDP write at given location and set cursor vars.
; A - xpos, Y - ypos, dont touch X
vdp_set_pos:	STA VDP_XPOS		; X
				STA VDP_CURS		; start abs curs position with X
				STY VDP_YPOS		; Y
				STZ VDP_CURS+1
				CPY #0				; if Y was 0 then we already have position
				BEQ vsp_done
vsp_loop:		CLC					; otherwise add screen width * Y
				LDA VDP_CURS
				ADC VDP_CHAR_WIDTH
				STA VDP_CURS
				LDA VDP_CURS+1
				ADC #0
				STA VDP_CURS+1
				DEY
				BNE vsp_loop
vsp_done:
				JSR vdp_start_str_w
				RTS
				 
;------------------------------------------------
; Write the zero terminated string pointed to by R0 to screen
; to current cursor pos
; Screen pos will wrap lines, but not pages
; The screen position is handled internaly - not suitable for BASIC inteface
vdp_write_text: 
				JSR vdp_start_str_w
				LDY #0				;; max 255 chars, in case not zero term
vps_next_char:  
				LDA (R0),Y
				BEQ vps_done		;; found zero in string
				CMP #$0A			;; Line feed
				BEQ vps_lf
				CMP #$0D			;; Carraige return
				BEQ vps_cr
				STA VDP_WR_VRAM		;; otherwise write the char
				JSR vdp_inc_pos
vps_get_next:	INY
				BNE vps_next_char
vps_done:		RTS

vps_lf:		 ;; move down a line
				JSR vdp_move_line_down
				JSR vdp_start_str_w
				JMP vps_get_next

vps_cr:		 ;; return to start of current line
				JSR vdp_move_to_start_line
				JSR vdp_start_str_w
				JMP vps_get_next

;---------------------------------------------
; Screen movement - handle vars for cursor pos
;	VDP_CURS - incremental char position 
;	VDP_XPOS - XPosition
;	VDP_YPOS - YPosition
; depends on
;	VDP_CHAR_WIDTH - 32 or 40
;
; increment screen position (preserve A)
;	wraps line
vdp_inc_pos:	PHA
				;; screen pos (name 0-32*24 or 0-40*24 for mode 0)
				INC VDP_CURS
				BNE @nowrap
				INC VDP_CURS+1
@nowrap:		INC VDP_XPOS
				LDA VDP_XPOS
				CMP VDP_CHAR_WIDTH	;; check end of line
				BEQ inc_pos_eol 
				PLA
				RTS
inc_pos_eol:	JSR vdp_move_to_start_line	;; CR
				JSR vdp_move_line_down	;; LF
				PLA
				RTS

; increment line (preserve A)
vdp_move_line_down:
				PHA
				LDA VDP_YPOS			;; first check if we are on bottom row
				CMP #23
				BEQ @bottom_row

				;; normal move down
				LDA VDP_CHAR_WIDTH ;; add line width to cusror position
				CLC
				ADC VDP_CURS		
				STA VDP_CURS
				LDA #0
				ADC VDP_CURS+1
				STA VDP_CURS+1
				INC VDP_YPOS		 ;; increment Y pos

				;; copy cursor
				add8To16 VDP_CHAR_WIDTH,ZP_COPY_CURS

				PLA
				RTS
				
@bottom_row:	;; scroll screen
				JSR vdp_scroll_up_line
				;; move to begining of row
				JSR vdp_move_to_start_line
				;; clear line
				JSR vdp_start_str_w
				TYA
				PHA
				LDY VDP_CHAR_WIDTH
				LDA #$20			;; and write a space
@loop_clrline:	JSR vdp_write
				DEY
				BNE @loop_clrline
				JSR vdp_move_to_start_line
				PLA
				TAY
				PLA
				RTS

; set X position to 0 as CR. (preserve A)
vdp_move_to_start_line:
				PHA
				SEC
				LDA VDP_CURS		 ;; get abs cursor pos
				SBC VDP_XPOS		 ;; and subtract X value
				STA VDP_CURS
				LDA VDP_CURS+1
				SBC #0
				STA VDP_CURS+1
				LDA #0
				STA VDP_XPOS		 ;; set x to 0, y unchanged
				PLA
				RTS

; decrement X position (preserve A)
vdp_move_back_char:
				PHA
				dec16 VDP_CURS		;; --VDPCursPos
				LDA VDP_XPOS
				BNE @move_back			;; if Xpos>0 just decrement Xpos
				;; XPos is 0 :- Move up and to end of line
				LDA VDP_YPOS
				BEQ @at_top_stop		;; but cant go up at all
				DEC VDP_YPOS			;; --YPos
				LDA VDP_CHAR_WIDTH
				STA VDP_XPOS			;; XPos to end of line ... (minus 1)
@move_back:		DEC VDP_XPOS			;; --Xpos
@at_top_stop:	PLA
				RTS

;===============================================================================
; Entry point for write char in Acc (used by basic)
; should sheck for BELL ($07) too
; printing of graphics characters?
;
vdp_write_char:
				CMP #$0A				;; Line feed
				BNE @check_cr
				JSR vdp_clear_cursor
				JSR vdp_move_line_down
				JSR vdp_cursor_off
				RTS
@check_cr:		CMP #$0D				;; Carriage return
				BNE @check_bksp
				JSR vdp_clear_cursor
				JSR vdp_move_to_start_line
				JSR vdp_cursor_off
				RTS
@check_bksp:	CMP #$08				;; Backspace
				BNE vwc_write_char
vdp_backspace:  
				JSR vdp_clear_cursor
				JSR vdp_move_back_char ;; move back
				JSR vdp_start_str_w
				LDA #$20				;; and write a space
				STA VDP_WR_VRAM
				JSR vdp_draw_cursor
				RTS
vwc_write_char: 
				JSR vdp_start_str_w ;; set position to VDP_CURS
				STA VDP_WR_VRAM		;; write the char
				JSR vdp_inc_pos
				JSR vdp_draw_cursor
				RTS

vdp_draw_cursor:
				pha
				LDA ZP_CURSOR
				BEQ @nocursor
				JSR vdp_start_str_w ;; set position to VDP_CURS
				;LDA #$1D
				STA VDP_WR_VRAM
@nocursor:		pla
				RTS

vdp_clear_cursor:
				pha
				LDA ZP_CURSOR
				BEQ @nocursor2
				JSR vdp_start_str_w ;; set position to VDP_CURS
				LDA #$20
				STA VDP_WR_VRAM
@nocursor2:		pla
				RTS
vdp_cursor_on:
				pha
				LDA #$1D
				STA ZP_CURSOR
				pla
				RTS
vdp_cursor_off:
				pha
				LDA #0
				STA ZP_CURSOR
				pla
				RTS
;===============================================================================

;------------------------------------------------------
; Scroll
;  32 char wide modes : 768 chars
;  		256+256+256-32
;  40 char wide mode (0) : 960 chars
;  		256+256+256+192-40
vdp_scroll_up_line:
				phay
				LDA VDP_REGS+2		;; hi address of name table (VDP_REG2 * 0x400)
				ASL
				ASL
				STA ZP_TMP2+1		;; store in DestAddr (hi)
				LDY #00		  
				STY ZP_TMP2			;; (lo)

				STA ZP_TMP0+1		;; SourceAddr is Base + screen width
				LDY VDP_CHAR_WIDTH
				STY ZP_TMP0
				
				LDY #00 			;; 256 chars		 
				STY TMP2
				JSR vdp_copy
				
				INC ZP_TMP0+1		;; next source page
				INC ZP_TMP2+1		;; next dest page

				JSR vdp_copy		;; 512 chars		 

				INC ZP_TMP0+1		;; next source page
				INC ZP_TMP2+1		;; next dest page

				LDA VDP_MODE		;; mode 0?
				CMP #0
				BEQ @domode0

				;; 32 char modes 

				LDY #224		  	;; another 256-32 chars
				STY TMP2			
				JSR vdp_copy
				play
				RTS

@domode0:		JSR vdp_copy

				INC ZP_TMP0+1		;; next source page
				INC ZP_TMP2+1		;; next dest page

				LDY #152			;; extra 152 chars for mode 0
				STY TMP2
				JSR vdp_copy

				play
				RTS

;================================================================
; write consective names to name table
; works for text and both graphics modes
;
vdp_load_number_name_table:
				JSR vdp_setaddr_name_table

				LDA #$00			;; name to start
				STA TMP0			
				LDY #3
				LDX #00
gt1_loop:		JSR vdp_write
				INC TMP0
				LDA TMP0
				INX
				BNE gt1_loop
				DEY
				BNE gt1_loop
				
				; check mode - text mode needs more chars
				LDA VDP_MODE
				CMP #0
				BNE gt1_done
				
				; TEXT mode - load a further (960-768) = 192 ($C0) chars
				LDA #$00
				STA TMP0
				LDX #$C0
gt1_loop2:	  JSR vdp_write
				INC TMP0
				LDA TMP0
				DEX
				BNE gt1_loop2
				
gt1_done:		RTS

; Multicolor mode setup (clear)
; Fill name table with a standard pattern 
; 00 01 02 03 04 ... 1F
; 00 01 02 03 04 ... 1F
; 00 01 02 03 04 ... 1F
; 00 01 02 03 04 ... 1F
; 20 21 22 23 24 ... 3F
; 20 21 22 23 24 ... 3F
; 20 21 22 23 24 ... 3F
; 20 21 22 23 24 ... 3F
; 40 41 ...
;	 24/4 rows * 32 cols = 192 ($C0)
; A0 A1 ...	  ... BF
;
; This allows pixels to be set to any color by
; loading pixels according to this pattern 
;
;	  Columns	0,1  2,3  4,5	6,7	8,9 .... 62,63
; Row 0 is bytes	0,	8,	10,	18,	20 ....  F8
; Row 1 is bytes	1,	9,	11,	19,	21 ....  F9
; Row 2 is bytes	2,	A,	12,	1A,	22 ....  FA
; Row ......
; Row 7 is bytes	7,	F,	17,	1F,	27 ....  FF
; Row 8 (add 255) 100, 108 ....
; Row 9			101, 109 ....
; ...
; Row 47 ...	  507, 50F				  .... 5FF
;
; To calculate byte address of point (X,Y):
;
; X,Y = (Y/8)*$100+(Y%8)+((X/2)*8)  
;
;		Hi Byte = Y>>3
;		Lo Byte = (Y & 7) + ((X>>1)<<3)
;		(X is odd - lower nibble, X is even - upper nibble)
;
vdp_load_mc_standard_name_table:
				; get name table
				LDY #00			 ;; Set VRAM address to name table (VDP_REG2 * 0x400)
				LDA VDP_REGS+2
				ASL
				ASL
				JSR vdp_set_addr_w

				LDA #0
				STA TMP0			;; name value at start of current row is stored in TMP0

vlsnt_loop3:	LDA #4
				STA TMP0+1			;; 4 rows the same - counter in here
				
vlsnt_loop2:	LDY #$20			;; count 32 chars per row
				LDX TMP0			;; starting name value for this row
vlsnt_loop1:	STX VDP_WR_VRAM
				NOP
				NOP
				NOP
				INX
				DEY
				BNE vlsnt_loop1
				DEC TMP0+1
				BNE vlsnt_loop2

				; 4 rows of 32 done, repeat till we get to end of screen (24 rows)
				LDA TMP0
				CLC
				ADC #$20			;; add 32 to name
				STA TMP0
				CMP #$c0
				BNE vlsnt_loop3

				; clear pattern table
				RTS

;================================================================
; Copy/Blit NN bytes from address SSSS to address DDDD
;	SSSS in ZP_TMP0/1 DDDD in ZP_TMP2/3 NN in TMP2
;
vdp_copy:		
				; read to CPU memory
				ld16 RES, page_buffer	;; set CPU address
				LDY ZP_TMP0				;; set VDP VRAM read address
				LDA ZP_TMP0+1			;; in ZP_TMP0/1
				JSR vdp_set_addr_r
				LDY #0
@loop1:			JSR vdp_read			;; read from VDP
				STA (RES),Y				;; save in CPU
				INY
				CPY TMP2				;; number of bytes (0=256)
				BNE @loop1

				; write back 
				ld16 RES, page_buffer	;; set CPU read address
				LDY ZP_TMP2				;; set VDP VRAM write address
				LDA ZP_TMP2+1			;; in ZP_TMP2/3
				JSR vdp_set_addr_w
				LDY #0
@loop2:		 LDA (RES),Y				;; read from CPU
				JSR vdp_write			;; write to VDP
				INY
				CPY TMP2				;; number of bytes (0=256)
				BNE @loop2

				RTS

;================================================================
; New: COPY CURSOR functions
;
; Enable: Set COPY CURSOR position to be (Current Curs Pos) - (Screen width)
vdp_cc_enable:
				pha
				phy
				LDA VDP_CURS
				STA ZP_COPY_CURS
				LDA VDP_CURS+1
				STA ZP_COPY_CURS+1
				sub8From16 VDP_CHAR_WIDTH, ZP_COPY_CURS
				jsr vdp_cc_on
				ply
				pla
				rts
vdp_cc_on:
				; draw cursor
				; 1. read char at pos
				JSR vdp_cc_read
				; 2. make reverse video
				ORA #$80
				; 3. write back
				JSR vdp_cc_write
				RTS

vdp_cc_off:
				; draw cursor
				; 1. read char at pos
				JSR vdp_cc_read
				; 2. make normal video
				AND #$7F
				; 3. write back
				JSR vdp_cc_write
				RTS

vdp_cc_read:
				phay
				LDA VDP_REGS+2		;; Load Name tab from Reg2
				ASL					;; NameTab Addr = reg2 * 0x400
				ASL
				CLC
				ADC ZP_COPY_CURS+1	;; add curs hi byte to screen hi (res in A)
				LDY ZP_COPY_CURS	;; add curs lo byte to screen lo (0)
				JSR vdp_set_addr_r
				play
				JSR vdp_read
				RTS
vdp_cc_write:
				phay
				LDA VDP_REGS+2		;; Load Name tab from Reg2
				ASL					;; NameTab Addr = reg2 * 0x400
				ASL
				CLC
				ADC ZP_COPY_CURS+1	;; add curs hi byte to screen hi (res in A)
				LDY ZP_COPY_CURS	;; add curs lo byte to screen lo (0)
				JSR vdp_set_addr_w  
				play
				JSR vdp_write
				RTS

; move the copy cursor
; move right
vdp_cc_move_right:
				pha
				phy
				JSR vdp_cc_off
				inc16 ZP_COPY_CURS
				JSR vdp_cc_on
				ply
				pla
				RTS
vdp_cc_move_left:
				pha
				phy
				JSR vdp_cc_off
				dec16 ZP_COPY_CURS
				JSR vdp_cc_on
				ply
				pla
				RTS
vdp_cc_move_up:
				pha
				phy
				JSR vdp_cc_off
				sub8From16 VDP_CHAR_WIDTH,ZP_COPY_CURS
				JSR vdp_cc_on
				ply
				pla
				RTS
vdp_cc_move_down:
				pha
				phy
				JSR vdp_cc_off
				add8To16 VDP_CHAR_WIDTH,ZP_COPY_CURS
				JSR vdp_cc_on
				ply
				pla
				RTS
vdp_cc_disable:
				pha
				phy
				JSR vdp_cc_off
				LDA #$FF
				STA ZP_COPY_CURS+1
				ply
				pla
				RTS
