; vim: ts=4 sw=4
; Pong 

.setcpu "65C02"

.include "macros.inc65"
.include "zeropage.inc65"
.include "acia.inc65"
.include "io.inc65"
.include "string.inc65"
.include "video.inc65"
.include "video_common.inc65"
.include "video_registers.inc65"
.include "sprite.inc65"
.include "bcd.inc65"
.include "kbdvia.inc65"
.include "sound.inc65"
.include "colors.inc65"
.include "scancodes.inc65"
.include "pckybd.inc65"

.export pong
.export PONG_IRQ

; pong vars in basic program area
pong_vars = $7000
pp_ballx  = pong_vars+0
pp_bally  = pong_vars+1
pp_batly  = pong_vars+2
pp_batry  = pong_vars+3
pp_ballxv = pong_vars+4; ball velocity in X
pp_ballyv = pong_vars+5; ball velocity in Y
pp_scorel = pong_vars+6
pp_scorer = pong_vars+7
pp_game   = pong_vars+8; Game state. 0=not started, 1=playing, FF=quit, FE=win message
;pp_kbdrow = pong_vars+9;
;pp_kbdcol = pong_vars+10;
IRQ_COUNT = pong_vars+9
IRQ_OLD   = pong_vars+10 ; 2 bytes
pp_interval = pong_vars+12  ; number of 1/60sec intervals between updating screen

pp_bsx_pos = pong_vars+15	  ; positive value of current ball speed in x
pp_bsy_pos = pong_vars+16	  ; positive value of current ball speed in x
pp_bsx_neg = pong_vars+17	  ; negative value of current ball speed in y
pp_bsy_neg = pong_vars+18	  ; negative value of current ball speed in y

pp_c0_vol	= pong_vars + 20;
pp_collision = pong_vars + 21
pp_coll_cnt  = pong_vars + 22
strbuf	   = pong_vars + 23;

BALLSPEEDX = $02			; starting ball speeds
BALLSPEEDXNEG = $FE
BALLSPEEDY = $02
BALLSPEEDYNEG = $FE

BATSPEED  = 4

BATL_POS = 16
BATR_POS = 238

; write to approx middle of screen 11*32=352=$0160
;  screen 9*32=288 = $120
;  screen 13*32=416 = $1A0
LINE_HI = $01
LINE9_LO = $20
LINE11_LO = $60
LINE13_LO = $A0

; IRQ location - points to address part of JMP xxxx
IRQ_ADDR = $20A

.bss
score_buffer:
	.res 4,0

.code

; Setup sprites for ball and bats
pp_sprite_pattern_start:
bat_left_sprite_top:
	.byte $40,$E0,$E0,$E0,$E0,$E0,$E0,$E0
bat_left_sprite_bot:
	.byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$40
bat_right_sprite_top:
	.byte $02,$07,$07,$07,$07,$07,$07,$07
bat_right_sprite_bot:
	.byte $07,$07,$07,$07,$07,$07,$07,$02
ball_sprite:
	.byte $3C,$7E,$FF,$FF,$FF,$FF,$7E,$3C
pp_char_pattern_start:
dot_line_char:
	.byte $00,$01,$01,$00,$00,$01,$01,$00
	.byte $00,$80,$80,$00,$00,$80,$80,$00

pong:
; sound channels all off
.ifdef SOUND
		JSR snd_all_off
.endif

; set mode
		LDA #1					; Graphics I mode
		JSR vdp_set_mode
		; Set main play area colors
		LDA #FG_WHITE
		ORA #BG_DRK_BLUE
		JSR vdp_load_flat_colors
		; set corder color
		LDA #FG_WHITE
		ORA #BG_LIT_GREEN
		LDY #$87
		JSR vdp_regwrite

; Init and Set sprite type (8x8 unmag)
		JSR vdp_init_sprites
		JSR spr_set_small
		JSR spr_set_mag_off
		LDA #5					; enable 5 sprites
		STA ZP_TMP0				; Pass number of sprites in ZP_TMP0
		JSR vdp_enable_sprites

; Load patterns
		ld16 ZP_TMP0, pp_sprite_pattern_start
		STZ ZP_TMP2				; load into P=0,1 ...
@next_pattern:
		JSR vdp_load_sprite_data_from_mem
		CLC
		add8To16 #8,ZP_TMP0		; move data ptr to next pattern
		INC ZP_TMP2				; inrement pattern numner
		LDA ZP_TMP2
		CMP #5
		BNE @next_pattern

; set sprite pattern, position, colour and early bit
		LDX #0					; X is sprite number (S)
		LDY VDP_SAB			; set address of Sprite Attribute table
		LDA VDP_SAB+1
		JSR vdp_set_addr_w
		LDY #0					; most fields are initially 0
		LDA #$0F				; Colour white / no early bit set
@next_sprite:
		STY VDP_WR_VRAM			; Pos X
.ifdef FASTCPU
		NOP
		NOP
		NOP
		NOP
		NOP
.endif
		NOP
		NOP
		STY VDP_WR_VRAM			; Pos Y
.ifdef FASTCPU
		NOP
		NOP
		NOP
		NOP
		NOP
.endif
		NOP
		NOP
		STX VDP_WR_VRAM			; Pattern
.ifdef FASTCPU
		NOP
		NOP
		NOP
		NOP
		NOP
.endif
		NOP
		NOP
		STA VDP_WR_VRAM			; Colour
.ifdef FASTCPU
		NOP
		NOP
		NOP
		NOP
		NOP
.endif
		INX
		CPX #5
		BNE @next_sprite

; disable ball sprite for now
		JSR disable_ball

; set patterns 0&1 to be dots for central line
		ld16 ZP_TMP0, dot_line_char
		JSR vdp_setaddr_pattern_table
		LDY #0
@load_char:
		LDA (ZP_TMP0),Y
		JSR vdp_write
		INY
		CPY #16
		BNE @load_char
		
; Draw board & Score
		JSR pp_draw_central_line

;; initialise game variables
		LDA #96-8
		STA pp_batly
		STA pp_batry
		STZ pp_scorel
		STZ pp_scorer
		LDA #60-4
		STA pp_bally
		LDA #80-4
		STA pp_ballx
		STZ pp_game

		LDA #BALLSPEEDX
		STA pp_bsx_pos
		STA pp_ballyv	   ; current ball speed
		LDA #BALLSPEEDY
		STA pp_bsy_pos
		STA pp_ballxv	   ; current ball speed
		LDA #BALLSPEEDXNEG
		STA pp_bsx_neg
		LDA #BALLSPEEDYNEG
		STA pp_bsy_neg

		JSR draw_score
;---------------------------------------
.if .def(PS2K) || .def(VKEYB)
; init keyboard
		jsr KBINIT
; set ps2 keyboard to have no repeat
		;jsr KBTMOFF
		lda #0
		sta KBD_FLAGS ; use KBD_FLAGS zp var to hold key flags
					  ; 7  6  5  4  3  2  1  0
					  ;				RD RU LD LU
					  ;				/  '  z  a
.endif

;=======================================
; Setup interrupt handler
pih_save_old:
		LDA IRQ_ADDR
		STA IRQ_OLD
		LDA IRQ_ADDR+1
		STA IRQ_OLD+1

		LDA #$01
		STA pp_interval
		STA IRQ_COUNT

pih_setup_new:
		LDA #<PONG_IRQ
		STA IRQ_ADDR
		LDA #>PONG_IRQ
		STA IRQ_ADDR+1

; Enable VDP IRQ output (every 1/60th second)
pih_enable_vdp_irq:
		LDA VDP_REGS+1	  ;; data to write is existing Reg1 (was set by MODE command)
		ORA #$20			;; with bit2 set - actually bit 5 if numbered from LSb like sensible chips
		STA VDP_REGS+1
		LDY #$81			;; register to write (1)
		JSR vdp_regwrite

		JSR vdp_getstatus   ;; clear interrupt flag in VDP

; Start allowing interrupts at CPU
		CLI

		LDA #LINE_HI
		STA VDP_CURS+1
		LDA #LINE9_LO
		STA VDP_CURS
		ld16 R0, msg_instructions
		JSR vdp_write_text
		LDA #LINE13_LO
		STA VDP_CURS
		ld16 R0, msg_press_s
		JSR vdp_write_text

;=======================================
; Game loop
game_loop:

		JSR get_input_serial

.if .def(PS2K) || .def(VKEYB)
		JSR get_input_ps2k
.endif

check_irq_count:
		LDA IRQ_COUNT
		BNE gl_skip_update
		;ld16 R0,irq_message
		;JSR acia_puts
		LDA pp_interval				 ;; start counting again (pp_interval * 1/60th)
		STA IRQ_COUNT

		JSR sound_vol	   ; reduce sound vol after a note

.ifdef KEYB
		JSR get_input_keyboard
.endif
.if .def(PS2K) || .def(VKEYB)
		JSR check_key_flags
.endif

		JSR draw_paddles

		LDA pp_game		; check game state:
		CMP #$00		; 	game not started?
		BEQ game_loop	; 		yes, keep just checking input and drawing paddles
		CMP #$02		;   pause state?
		BEQ game_loop
		CMP #$FF		; 	quit requested?
		BNE gl_dogame	; 		no, then continue
		JMP quit_game	; 		yes, quit
gl_dogame:
		JSR move_ball
		JSR draw_ball
		JSR check_game
		JSR draw_score

gl_skip_update:
		JMP game_loop

;---------------------------------------
; Get input from ACIA
get_input_serial:

		LDA ACIA_STATUS
		AND #ACIA_STATUS_RX_FULL
		BEQ gi_done
		LDA ACIA_DATA
gi_got_key:
;		CMP #'a'
;		BEQ gi_movelup
;		CMP #'z'
;		BEQ gi_moveldown
;		CMP #';'
;		BEQ gi_moverup
;		CMP #'.'
;		BEQ gi_moverdown
		CMP #'q'
		BNE gi_check_s
		LDA #$FF
		STA pp_game
		JMP gi_done
gi_check_s:
		CMP #'s'
		BNE gi_check_minus
		LDA #$01
		STA pp_game
		JSR pp_clear_message
		JMP gi_done
gi_check_minus:
		CMP #'-'
		BNE gi_check_plus
		DEC pp_interval
		JSR gi_print_interval

gi_check_plus:
		CMP #'+'
		BNE gi_done
		INC pp_interval

gi_print_interval:
		ld16 R0,strbuf
		LDA pp_interval
		JSR fmt_hex_string
		JSR acia_puts
		JSR acia_put_newline
		
gi_done:
		RTS

gi_movelup:
		LDA pp_batly
		CMP #BATSPEED			; top=0+BATSPEED
		BCC gi_done				; A < top
		SEC
		LDA pp_batly
		SBC #BATSPEED
		STA pp_batly
		RTS
gi_moveldown:
		LDA pp_batly
		CMP #193-16-BATSPEED	; bot=193-BATSIZE-BATSPEED
		BCS gi_done				; A >= bot
		CLC
		LDA pp_batly
		ADC #BATSPEED
		STA pp_batly
		RTS
gi_moverup:
		LDA pp_batry
		CMP #BATSPEED			; top=0+BATSPEED
		BCC gi_done				; A < top
		SEC
		LDA pp_batry
		SBC #BATSPEED
		STA pp_batry
		RTS
gi_moverdown:
		LDA pp_batry
		CMP #193-16-BATSPEED	; bot=193-BATSIZE-BATSPEED
		BCS gi_done				; A >= bot
		CLC
		LDA pp_batry
		ADC #BATSPEED
		STA pp_batry
		RTS

pp_draw_central_line:
; Central dotted line
		LDX #24				; height mode 1
		LDA VDP_REGS+2	  ; Name table
		ASL
		ASL
		STA ZP_TMP0+1
		LDA #$0F			; start at position 15
		STA ZP_TMP0
@loop1:
		LDY ZP_TMP0			; set vram write addr
		LDA ZP_TMP0+1
		JSR vdp_set_addr_w
		LDA #0				; write 2 chars to split centre
		JSR vdp_write
		LDA #1
		NOP
		JSR vdp_write
		
		add8To16 #$20, ZP_TMP0 ; add screen width
		DEX
		BNE @loop1
		RTS

pp_clear_message:
		; clear approx middle of screen 11*32+16-7=361=$0169
		LDA #LINE_HI
		STA VDP_CURS+1
		LDA #LINE9_LO
		STA VDP_CURS
		ld16 R0, msg_clear
		JSR vdp_write_text
		LDA #LINE11_LO
		STA VDP_CURS
		JSR vdp_write_text
		LDA #LINE13_LO
		STA VDP_CURS
		JSR vdp_write_text
		JSR pp_draw_central_line
		RTS

.ifdef KEYB
;---------------------------------------
; Get input from KEYBOARD
get_input_keyboard:
		JSR kbd_getkey			  ; result in KBD_COL, KBD_ROW (zero-page)
		BCC gik_done

gik_got_key:
		; "spc" q in row 0 col 4, 6
		; azs are in row 1 cols 2,4,5
		; ":" ";" row 2,3

		LDX #0
		LDA scan_buffer,X
		AND #%00010000			  ; ROW0 COL4 = "spc"
		BEQ @check_q

		JSR pp_clear_message
		LDA #$01					; game state = playing
		STA pp_game
@check_q:
		LDA scan_buffer,X
		AND #%01000000			  ; ROW0 COL6 = "q"
		BEQ gik_test_row1
		LDA #$FF					; else mark end-of-game
		STA pp_game				 ; in game state variable

gik_test_row1:
		LDX #1
		LDA scan_buffer,X
		AND #%00000100			; ROW1 COL2 = "a"
		BEQ @check_z
		JSR gi_movelup
@check_z:
		LDA scan_buffer,X
		AND #%00010000			; ROW1 COL4 = "z"
		BEQ @check_s
		JSR gi_moveldown
@check_s:
		LDA scan_buffer,X
		AND #%00100000			; ROW1 COL5 = "s"
		BEQ gik_test_row6
		LDA #$01
		STA pp_game
		JSR pp_clear_message

gik_test_row6:
		LDX #6
		LDA scan_buffer,X
		AND #%00000100			; ROW6 COL2 = ";"
		BEQ @check_m
		JSR gi_moverup
@check_m:
		LDA scan_buffer,X
		AND #%00001000			; ROW6 COL3 = "\"
		BEQ gik_done
		JSR gi_moverdown

gik_done:
		RTS
.endif

.if .def(PS2K) || .def(VKEYB)
check_key_flags:
		lda #1
		bit KBD_FLAGS
		beq @next1
		jsr gi_movelup
	@next1:
		lda #2
		bit KBD_FLAGS
		beq @next2
		jsr gi_moveldown
	@next2:
		lda #4
		bit KBD_FLAGS
		beq @next3
		jsr gi_moverup
	@next3:
		lda #8
		bit KBD_FLAGS
		beq @over
		jsr gi_moverdown
	@over:
		rts

;-----------------------------------------------------
; This sets the KBD_FLAGS variable as above
;
get_input_ps2k:
		jsr KBSCAN_GAME
		bcc gip_done
		
		; debug
		;lda #'['
		;jsr acia_putc
		;ld16 R0,score_buffer
		;lda KBD_CHAR
		;jsr fmt_hex_string
		;jsr acia_puts
		;lda #':'
		;jsr acia_putc
		;lda KBD_SPECIAL
		;jsr fmt_hex_string
		;jsr acia_puts
		;lda #']'
		;jsr acia_putc
		; enddebug
		ldx #0				  ; 0 in X means this is a make code
		lda KBD_CHAR
		cmp #SC_SPECIAL		 ; check for a break code
		bne gip_skip_set_breakcode

		lda KBD_SPECIAL		 ; get break code
		;beq gip_done
		ldx #1				  ; 1 in X means this is a break code
		
gip_skip_set_breakcode:
		cmp #SC_A
		beq gip_do_LP_UP
		cmp #SC_Z
		beq gip_do_LP_DOWN

		cmp #SC_TICK
		beq gip_do_RP_UP
		cmp #SC_RAW_UP_ARROW
		beq gip_do_RP_UP
		cmp #SC_NC_UP_ARROW
		beq gip_do_RP_UP

		cmp #SC_FWDSLASH
		beq gip_do_RP_DOWN
		cmp #SC_RAW_DOWN_ARROW  ; raw scan code (converted)
		beq gip_do_RP_DOWN
		cmp #SC_NC_DOWN_ARROW   ; raw scan code (not converted) (needed for break codes of arrow keys)
		beq gip_do_RP_DOWN

		cmp #SC_S
		beq gip_do_START
		cmp #SC_SPC
		beq gip_do_START
		cmp #SC_Q
		beq gip_do_QUIT
		
gip_done:
		rts

gip_do_QUIT:
		LDA #$FF
		STA pp_game
		rts
gip_do_START:
		LDA #$01
		STA pp_game
		JSR pp_clear_message
		rts

gip_do_LP_UP:
		cpx #0
		beq @do_make
		RMB0 KBD_FLAGS	  ; key unpressed - unset bit 0
		rts
  @do_make:
		SMB0 KBD_FLAGS	  ; key was pressed - set bit 0
		rts

gip_do_LP_DOWN:
		cpx #0
		beq @do_make
		RMB1 KBD_FLAGS
		rts
  @do_make:
		SMB1 KBD_FLAGS
		rts

gip_do_RP_UP:
		cpx #0
		beq @do_make
		RMB2 KBD_FLAGS
		rts
  @do_make:
		SMB2 KBD_FLAGS
		rts

gip_do_RP_DOWN:
		cpx #0
		beq @do_make
		RMB3 KBD_FLAGS
		rts
  @do_make:
		SMB3 KBD_FLAGS
		rts

.endif

;---------------------------------------
; Draw paddles
draw_paddles:
		;; draw left paddle
		LDA #0
		STA ZP_TMP0		; S
		LDA #BATL_POS
		STA ZP_TMP0+1	; X
		LDA pp_batly
		STA ZP_TMP2		; Y
		JSR vdp_set_sprite_pos
		LDA #1
		STA ZP_TMP0		; S
		LDA #BATL_POS
		STA ZP_TMP0+1	; X
		LDA pp_batly
		CLC
		ADC #8
		STA ZP_TMP2		; Y+8
		JSR vdp_set_sprite_pos
		;; draw right paddle
		LDA #2
		STA ZP_TMP0		; S
		LDA #BATR_POS
		STA ZP_TMP0+1	; X
		LDA pp_batry
		STA ZP_TMP2		; Y
		JSR vdp_set_sprite_pos
		LDA #3
		STA ZP_TMP0		; S
		LDA #BATR_POS
		STA ZP_TMP0+1	; X
		LDA pp_batry
		CLC
		ADC #8
		STA ZP_TMP2		; Y+8
		JSR vdp_set_sprite_pos
		RTS

;--------------------------------------------------
; Check ball position and change speed as necessary
; Move the ball according to current speed
;
move_ball:
		; if y<top or y>bot then invert yspeed
		LDA pp_bally
		CMP #1
		BCC mb_yspeed_pos	; A < ballspeed y, bounce
		CMP #192-8
		BCS	mb_yspeed_neg	; ball is at bottom edge, bounce
		JMP mb_check_collision
mb_yspeed_pos:
		LDA pp_bsy_pos		; make Y-velocity positive
		STA pp_ballyv
		JSR sound_pong
		JMP mb_check_collision
mb_yspeed_neg:
		LDA pp_bsy_neg		; make Y-velocity negative
		STA pp_ballyv		;
		JSR sound_pong
		JMP mb_check_collision

; X direction

mb_check_collision:
		lda pp_coll_cnt		 ; period during which we ignore collisions to stop in-bat bounce
		beq mcc_do_detect
		dec pp_coll_cnt
		STZ pp_collision		; reset
		jmp mb_add_speed		; not considering collision

mcc_do_detect:
		; sprite collision detection
		LDA pp_collision
		BEQ mb_add_speed		; no collision

		; sprite collision
		STZ pp_collision		; reset
		lda #$10				; number of cycles we ignore collisions for
		sta pp_coll_cnt
		LDA pp_ballxv
		BPL mb_xspeed_neg

		; hit bat - make ball speed positive again
mb_xspeed_pos:
		LDA pp_bsx_pos
		STA pp_ballxv
		JSR sound_ping
		JMP mb_add_speed

mb_xspeed_neg:
		LDA pp_bsx_neg
		STA pp_ballxv
		JSR sound_ping
		JMP mb_add_speed

mb_add_speed:
		; add speed to x/y
		CLC
		LDA pp_ballx
		ADC pp_ballxv
		STA pp_ballx
		CLC
		LDA pp_bally
		ADC pp_ballyv
		STA pp_bally
		RTS

;---------------------------------------
; Draw ball
draw_ball:
		;; draw ball
		LDA #4			; S=4 ball sprite
		STA ZP_TMP0
		LDA pp_ballx
		STA ZP_TMP0+1	; X 
		LDA pp_bally
		STA ZP_TMP2		; Y
		JSR vdp_set_sprite_pos
		RTS

;---------------------------------------
; Disable ball sprite
disable_ball:
		LDA VDP_SAB			; set address of Sprite Attribute table
		CLC
		ADC #16
		TAY
		LDA VDP_SAB+1
		JSR vdp_set_addr_w
		LDA #$D0
		JSR vdp_write
		RTS

;---------------------------------------
; Draw score
draw_score:
		LDA #10
		JSR ds_set_cursor_position
		LDA pp_scorel
		CMP #100				; check if triple digit
		BCS ds_over				; X >= 100
		INC VDP_CURS			; move right
		CMP #10					; check if double digits
		BCS ds_over				; X >= 10, X < 100
		INC VDP_CURS			; move right
ds_over:
		LDA pp_scorel			; Left score
		JSR ds_conv_decimal		; convert to decimal string in R0
		JSR vdp_write_text		; write the string

		LDA #19					; x position to put score
		JSR ds_set_cursor_position
		LDA pp_scorer
		JSR ds_conv_decimal
		JSR vdp_write_text		; write the string
		RTS

ds_conv_decimal:
		; A has number, convert to bcd in RES, RES+1
		JSR BINBCD8
		; Convert BCD number in RES to string pointed to in R0
		ld16 R0, score_buffer
		JSR BCD2STR
		RTS
		
ds_set_cursor_position:
		; A has x position, y pos is 2
		; Set cursor position in VDP_CURS
		CLC
		ADC #64					; set Y=2 on a graphics screen
		STA VDP_CURS
		STZ VDP_CURS+1
		STA VDP_XPOS
		LDA #2
		STA VDP_YPOS
		RTS

msg_press_space:
	;	  01234567890123456789012345678901
	.byte "	Press Space to continue	 ",$00
msg_instructions:
	.byte " Left A Z   Q=Quit   Right  ' / ",$00
msg_press_s:
	.byte "	  Press 'S' to start		",$00
msg_clear:
	.byte "								",$00
pp_pause_game:
		LDA #LINE_HI
		STA VDP_CURS+1
		LDA #LINE11_LO
		STA VDP_CURS
		ld16 R0, msg_press_space
		JSR vdp_write_text
		LDA #$02				; put game into pause state
		STA pp_game
		RTS
		
;---------------------------------------
; Check game conditions
; Check ball position - if going off left, inc R score
check_game:

		; Check if ball has gone off left
		LDA pp_ballx
		CMP #2
		BCS cg_check_right		; still in play (X>0)

		; Right player has scored
		LDA pp_scorer
		INC
		STA pp_scorer
		JSR sound_score
		JSR pp_pause_game

		LDA #124				; reset ball position
		STA pp_ballx
		LDA pp_bsx_pos
		STA pp_ballxv		
		JSR draw_ball

		JMP cg_check_scores

cg_check_right:
		; Check if ball has gone off right
		LDA pp_ballx
		CMP #253
		BCC cg_check_scores		; still in play (X<256)

		; Left player has scored
		LDA pp_scorel
		INC
		STA pp_scorel
		JSR sound_score
		JSR pp_pause_game

		LDA #96					; reset ball position
		STA pp_ballx
		LDA pp_bsx_neg
		STA pp_ballxv		
		JSR draw_ball

cg_check_scores:
		LDA pp_scorel
		CMP #10
		BCS cg_left_wins
		LDA pp_scorer
		CMP #10
		BCS cg_right_wins
cg_done:
		RTS

cg_left_wins:
		ld16 R0, win_left_message
		JMP cg_write_win_message
cg_right_wins:
		ld16 R0, win_right_message
cg_write_win_message:
		JSR acia_puts
		JSR acia_put_newline
		LDA #$FE
		STA pp_game

		LDA #LINE_HI
		STA VDP_CURS+1
		LDA #LINE11_LO
		STA VDP_CURS
		JSR vdp_write_text
	   
		RTS
;---------------------------------------
;
quit_game:
		ld16 R0,quit_message
		JSR acia_puts
; restore interrupt vector 
pih_restore_irq:
		LDA IRQ_OLD
		STA IRQ_ADDR
		LDA IRQ_OLD+1
		STA IRQ_ADDR+1
; disable interrupts at CPU
		SEI

; disable interrupts from VDP
		LDA VDP_REGS+1	  ;; data to write is existing Reg1
		AND #$DF			;; unset interrupt bit
		STA VDP_REGS+1
		LDY #$81			;; register to write (1)
		JSR vdp_regwrite

		JSR vdp_getstatus   ;; clear interrupt flag in VDP

.ifdef SOUND
		; stop any sounds
		JSR snd_all_off
.endif
.if .def(PS2K) || .def(VKEYB)
		; reenable typematic repeat
		jsr KBTMON
.endif
		LDA #0
		JSR vdp_set_mode
		RTS

;---------------------------------------
; Interrupt handler
PONG_IRQ:
		PHA

		JSR vdp_getstatus		   ;; read VDP status to reenable the VDP interrupt
		; sprite collision detection
		LDA VDP_STATUS
		AND #%00100000
		BEQ @no_colision
		LDA #1
		STA pp_collision
@no_colision:
		LDA IRQ_COUNT			   ;; if count >0
		BEQ @skip
		DEC IRQ_COUNT			   ;; count--
@skip:
		PLA
		RTI
;---------------------------------------

quit_message:
	.byte "Goodbye!",$0d,$0a,$00
win_left_message:
	.byte "Player 1 Wins!",$0d,$0a,$00
win_right_message:
	.byte "Player 2 Wins!",$0d,$0a,$00
irq_message:
	.byte "Hello",$0d,$0a,$00

.ifdef SOUND
sound_vol:
		LDA pp_c0_vol
		CMP #$0F
		BCS @over
		INC pp_c0_vol
		LDA #%10010000 ; c0 vol
		ORA pp_c0_vol
		JSR snd_write
@over:
		RTS
sound_ping:
		; Set frequency to %0001111111 = 127 -> 3.6864MHz/32*127 = 907Hz
		LDA #%10001111  ; Freq Channel 1 (of 3)
		JSR snd_write
		LDA #%00000111  ; Freq DDDDDD 
		JSR snd_write
		LDA #%10010000 ; c0 vol = full (0)
		JSR snd_write
		STZ pp_c0_vol
		RTS
sound_pong:
		; Set frequency to %0100000110 = 262 -> 3.6864MHz/32*262 ~= 440Hz
		LDA #%10000110  ; Freq Channel 1 (of 3)
		JSR snd_write
		LDA #%00010000  ; Freq DDDDDD 
		JSR snd_write
		LDA #%10010000 ; c0 vol = full (0)
		JSR snd_write
		STZ pp_c0_vol
		RTS
sound_score:
		RTS
.else
sound_vol:
sound_ping:
sound_pong:
sound_score:
		RTS
.endif
