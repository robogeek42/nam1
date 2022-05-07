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

.export breakout
.export BOUT_IRQ

; breakout vars in basic program area
bout_vars = $7000

ballx	= bout_vars+0
bally	= bout_vars+1
ballxv	= bout_vars+4		; ball velocity in X
ballyv	= bout_vars+5		; ball velocity in Y
batx    = bout_vars+6		; left pos of bat

br_game		= bout_vars+8; Game state. 0=not started, 1=playing, FF=quit, FE=win message
IRQ_COUNT	= bout_vars+9
IRQ_OLD		= bout_vars+10 ; 2 bytes
bo_interval	= bout_vars+12  ; number of 1/60sec intervals between updating screen
IRQ_EVENT   = bout_vars+13

br_c0_vol	= bout_vars+20;
strbuf		= bout_vars+21;

; IRQ location - points to address part of JMP xxxx
IRQ_ADDR = $20A

.bss
score_buffer:
	.res 4,0

.code

breakout:
; sound channels all off
.ifdef SOUND
		JSR snd_all_off
.endif

; set mode
		LDA #3					; Multicolor Graphics mode
		JSR vdp_set_mode
		; Set main play area colors
		;LDA #FG_WHITE
		;ORA #BG_DRK_BLUE
		;JSR vdp_load_flat_colors
		; set border color
		LDA #FG_WHITE
		ORA #BG_LIT_GREEN
		LDY #$87
		JSR vdp_regwrite

		; clear screen to pattern
		JSR vdp_load_mc_standard_name_table

; Draw board
        JSR draw_board

;; initialise game variables
		STZ br_game

	; starting bat position
		LDA #30
		STA batx
		
	; starting ball position and sped
		LDA #32 
		STA ballx
		LDA #46 
		STA bally
		LDA #$01
		STA ballxv
		LDA #$FF
		STA ballyv

;---------------------------------------
.if .def(PS2K) || .def(VKEYB)
; init keyboard
		jsr KBINIT
		lda #0
		sta KBD_FLAGS ; use KBD_FLAGS zp var to hold key flags
					  ; 7  6  5  4  3  2  1  0
					  ;				      L  R
					  ;				      z  x
.endif

;=======================================
; Setup interrupt handler
pih_save_old:
		LDA IRQ_ADDR
		STA IRQ_OLD
		LDA IRQ_ADDR+1
		STA IRQ_OLD+1

		LDA #$03
		STA bo_interval
		STA IRQ_COUNT
		LDA #0
		STA IRQ_EVENT

pih_setup_new:
		LDA #<BOUT_IRQ
		STA IRQ_ADDR
		LDA #>BOUT_IRQ
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

;=======================================
; Game loop
game_loop:

		JSR get_input_serial

.if .def(PS2K) || .def(VKEYB)
		JSR get_input_ps2k
.endif

check_irq_count:
		LDA IRQ_EVENT
		BEQ gl_skip_update
		LDA #0
		STA IRQ_EVENT

.if .def(PS2K) || .def(VKEYB)
		JSR check_key_flags
.endif
		JSR draw_paddle

		LDA IRQ_COUNT
		CMP #0
		BNE gl_skip_update
		LDA bo_interval		 ;; start counting again (bo_interval * 1/60th)
		STA IRQ_COUNT

		JSR sound_vol       ; reduce sound vol after a note

		LDA br_game		; check game state:
		CMP #$00		; 	game not started?
		BEQ game_loop	; 		yes, keep just checking input and drawing paddles
		CMP #$02		;   pause state?
		BEQ game_loop
		CMP #$FF		; 	quit requested?
		BNE gl_dogame	; 		no, then continue
		JMP quit_game	; 		yes, quit
gl_dogame:
		JSR clear_ball
		JSR move_ball
		JSR draw_ball

		JSR check_game
		;JSR draw_score

gl_skip_update:
        JMP game_loop

;---------------------------------------
; Interrupt handler
BOUT_IRQ:
		PHA

		JSR vdp_getstatus		   ;; read VDP status to reenable the VDP interrupt
		LDA IRQ_COUNT			   ;; if count >0
		BEQ @skip
		DEC IRQ_COUNT			   ;; count--
@skip:
		LDA #1
		STA IRQ_EVENT
		PLA
		RTI
;---------------------------------------


;---------------------------------------
; Get input from ACIA
get_input_serial:
		LDA ACIA_STATUS
		AND #ACIA_STATUS_RX_FULL
		BEQ gi_done
		LDA ACIA_DATA

		CMP #'z'
        BEQ gi_move_left
		CMP #'x'
        BEQ gi_move_right
		CMP #'q'
        BEQ gi_do_QUIT

gi_check_space:
		CMP #' '
        BEQ gi_do_START

gi_done:
		RTS

gi_do_QUIT:
		LDA #$FF
		STA br_game
		rts
gi_do_START:
		LDA #$01
		STA br_game
		rts

gi_move_left:
		LDA batx
		DEC
		BMI giml_over
		STA batx
	giml_over:
		RTS
gi_move_right:
		LDA batx
		INC
		CMP #59
		BCS gimr_over
		STA batx
	gimr_over:
		RTS
;---------------------------------------
.if .def(PS2K) || .def(VKEYB)
check_key_flags:
		lda #1
		bit KBD_FLAGS
		beq @next1
        jsr gi_move_right
	@next1:
		lda #2
		bit KBD_FLAGS
        beq @over
        jsr gi_move_left
	@over:
		rts

;-----------------------------------------------------
; This sets the KBD_FLAGS variable as above
;
get_input_ps2k:
		jsr KBSCAN_GAME
		bcc gip_done
		
		ldx #0				  ; 0 in X means this is a make code
		lda KBD_CHAR
		cmp #SC_SPECIAL		 ; check for a break code
		bne gip_skip_set_breakcode

		lda KBD_SPECIAL		 ; get break code
		;beq gip_done
		ldx #1				  ; 1 in X means this is a break code
		
gip_skip_set_breakcode:
		cmp #SC_Z
		beq gip_do_LEFT
		cmp #SC_COMMA
		beq gip_do_LEFT
		cmp #SC_X
		beq gip_do_RIGHT
		cmp #SC_DOT
		beq gip_do_RIGHT

		cmp #SC_S
		beq gi_do_START
		cmp #SC_SPC
		beq gi_do_START
		cmp #SC_Q
		beq gi_do_QUIT
		
gip_done:
		rts

gip_do_RIGHT:
		cpx #0
		beq @do_make
		RMB0 KBD_FLAGS	  ; key unpressed - unset bit 0
		rts
  @do_make:
		SMB0 KBD_FLAGS	  ; key was pressed - set bit 0
		rts

gip_do_LEFT:
		cpx #0
		beq @do_make
		RMB1 KBD_FLAGS
		rts
  @do_make:
		SMB1 KBD_FLAGS
		rts

.endif

;---------------------------------------
; Check game conditions
check_game:
		RTS

;--------------------------------------------------
; return the VDP address of any pos X,Y in TMP1
; X and Y are in TMP2
get_mc_point_address:
		; Calculate address to write to
		; Address (Ydiv8)*256 + Ymod8 + (Xdiv2)*8
		; store addess in TMP1 (2 bytes)
		
		; (Ydiv8)*256 is putting Ydiv8 into high byte
		LDA TMP2+1		; Y
		LSR				; y div 2
		LSR				; y div 4
		LSR				; y div 8
		STA TMP1+1

		; now add Y mod 8, so this is putting Y mod 8 into low byte
		LDA TMP2+1		; Y
		AND #$07
		STA TMP1
		
		; finally add Xdiv2 * 8 (X<64 so this will fit in a byte)
		LDA TMP2  		; X
		AND #$FE
		ASL
		ASL
		; now add to TMP1
		ADC TMP1
		STA TMP1
		LDA TMP1+1
		ADC #0
		STA TMP1+1
		RTS

;---------------------------------------
; Draw ball
draw_ball:
		LDA ballx
		STA TMP2
		LDA bally
		STA TMP2+1
		JSR get_mc_point_address 	; read into TMP1

		; start write on VDP at correct address
		LDA TMP1+1
		LDY TMP1
		JSR vdp_set_addr_w
		; calc byte and write to pattern table (starts at 0)
		LDA ballx				; Check if X is odd/even to get correct nybble
		AND #1
		BEQ db_hi_nybble
		LDA #$0F
		JSR vdp_write
		RTS
	db_hi_nybble:
		LDA #$F0
		JSR vdp_write
		RTS
		
;---------------------------------------
; Clear ball
clear_ball:
		LDA ballx
		STA TMP2
		LDA bally
		STA TMP2+1
		JSR get_mc_point_address 	; read into TMP1

		; read byte at ball address
		LDA TMP1+1
		LDY TMP1
		JSR vdp_set_addr_r
		JSR vdp_read
		PHA

		; start write on VDP at correct address
		LDA TMP1+1
		LDY TMP1
		JSR vdp_set_addr_w
		; calc byte and write to pattern table (starts at 0)
		LDA ballx				; Check if X is odd/even to get correct nybble
		AND #1
		BEQ cb_hi_nybble
	; low nybble
		PLA
		AND #$F0
		JSR vdp_write
		RTS
	cb_hi_nybble:
		PLA
		AND #$0F
		JSR vdp_write
		RTS
		
;--------------------------------------------------
; Read color under pos TMP2
; return in Acc
;
read_col_at_pos:
		JSR get_mc_point_address ; read into TMP1
		LDA TMP1+1
		LDY TMP1
		JSR vdp_set_addr_r
		JSR vdp_read
		PHA
		LDA TMP2				; Check if X is odd/even to get correct nybble
		AND #1
		BEQ rb_hi_nybble
		PLA
		AND #$0F
		RTS
	rb_hi_nybble:
		PLA
		LSR
		LSR
		LSR
		LSR
		RTS

;--------------------------------------------------
; Read color under the ball
; return in Acc
;
read_ball:
		LDA ballx
		STA TMP2
		LDA bally
		STA TMP2+1
		JSR read_col_at_pos
		
;--------------------------------------------------
; Check ball position and change speed as necessary
; Move the ball according to current speed
;    logic:
;      -- current ball position in ballx/y
;         current movement velocity in ballxv/yv
;      -- next ball position in TMP2/TMP2+1 == nextx/y
;      1. Add XV to X -> nextx
;      2. IF X<0 or X>64 reverse XV
;         - Add XV to X -> nextx
;      3. Add YV to Y -> nexty
;      4. IF Y>48 reverse YV
;         - Add YV to Y -> nexty
;         IF Y<0 ==> new ball
;
;      -- TMP2(nextx/y) contains next position including wall bounce
;
;      5. Check under next ball position (Acc -> NextCol)
;         IF NextCol == WHITE reverse Y 
;           Adjust YV/XV 
;           Add YV to Y -> nexty
;
;	   6. IF NextCol != BLACK Reverse YV
;	      Remove Brick
;	      Add YV tio Y -> nexty
;
;      7. Finalise movment TMP2 -> ballx/y
;
move_ball:

; Check walls
; 1. Add XV to X -> nextx
		CLC	
		LDA ballxv
		ADC ballx
		STA TMP2

; 2. IF X<0 or X>64 reverse XV
		CMP #0
		BMI mb_reverse_xv
		CMP #64
		BCS mb_reverse_xv
		JMP mb_do_y
	mb_reverse_xv:
		LDA ballxv
		TWOSCOMP				; 2s complement
		STA ballxv
; - Add XV to X -> nextx
		CLC
		ADC ballx				; to X
		STA TMP2				; and save
	
; 3. Add YV to Y -> nexty
mb_do_y:
		CLC
		LDA ballyv
		ADC bally
		STA TMP2+1
		
; 4. IF Y>48 reverse YV
		CMP #48
		BCS mb_reverse_yv		; Y >= 48
		CMP #0
		BMI mb_reverse_yv		; Y < 0 ... should be newball_score
		JMP mb_hit_check
	mb_reverse_yv:
		LDA ballyv
		TWOSCOMP
		STA ballyv
	; - Add YV to Y -> nexty
		CLC
		ADC bally				; add new speed to Y
		STA TMP2+1				; and save

; 5. Check under next ball position (Acc -> NextCol)
mb_hit_check:

;		JSR read_col_at_pos
;
;; IF NextCol == WHITE reverse Y 
;		CMP #15
;		BEQ mb5_reverse_y
;		JMP mb_check_brick
;mb5_reverse_y:
;	; Adjust YV/XV 
;		; so far just bounce evenly
;		LDA ballyv
;		TWOSCOMP
;		STA ballyv
;	; Add YV to Y -> nexty
;		CLC
;		ADC bally				; add new speed to Y
;		STA TMP2+1				; and save

; 5. detect bat position
		; if ball nexty >=46 
		LDA TMP2+1				; nexty
		CMP #46
		BCC mb_nohit1			; < 46

		LDA TMP2				; nextx
		CMP batx
		BCS mb_nohit1			; Ball < Batx (left)
		ADC #3
		CMP batx
		BCC mb_nohit1
	; Adjust YV/XV 
		LDA ballyv
		TWOSCOMP
		STA ballyv
	; Add YV to Y -> nexty
		CLC
		ADC bally				; add new speed to Y
		STA TMP2+1				; and save
mb_nohit1:

mb_check_brick:
;	   6. IF NextCol != BLACK Reverse YV
;	      Remove Brick
;	      Add YV to Y -> nexty
;		JSR read_col_at_pos

;
;      7. Finalise movment TMP2 -> ballx/y
mb_store_final:
		; change is good
		LDA TMP2
		STA ballx				; store new X
		LDA TMP2+1
		STA bally				; store new Y
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

;----------------------------------------------------------------------
; Draw board
;
draw_board:

		RTS

;----------------------------------------------------------------------
; Draw paddle - width 6 pixels
draw_paddle:
		; check if batx is even or odd
		; if even store $FF in X, odd store $0F - this wil be 1st write
		LDA batx
		ROR
		BCC db_iseven
		LDX #$0F
		JMP db_overif
	db_iseven:
		LDX #$FF
		; also need to clear previous position so bat moving right 
		; cleared behind it
		;
		; convert batx-2 to position on line $05*6, this will be X*4
		LDA batx
		DEC
		DEC
		LSR
		ASL
		ASL
		ASL
		; Add $0506
		CLC
		ADC #$06
		TAY
		LDA #$05
		JSR vdp_set_addr_w
		LDA #$00
		JSR vdp_write

	db_overif:
		; convert batx to position on line $05*6, this will be X*4
		LDA batx
		LSR
		ASL
		ASL
		ASL
		; Add $0506
		CLC
		ADC #$06
		TAY
		LDA #$05
		JSR vdp_set_addr_w
		JSR vdp_writex
		; move to next dot-pair and write $FF
		TYA 
		CLC
		ADC #$08
		TAY
		LDA #$05
		JSR vdp_set_addr_w
		LDA #$FF
		JSR vdp_write
		; move to next dot-pair and write $FF
		TYA 
		CLC
		ADC #$08
		TAY
		LDA #$05
		JSR vdp_set_addr_w
		LDA #$FF
		JSR vdp_write
		; last byte write, either $F0 (batx was odd) or $00
		; has effect of overwriting previous bat pos if bat is moving left
		LDA batx
		ROR
		BCC db_iseven2
		LDX #$F0
		JMP db_overif2
	db_iseven2:
		LDX #$0
	db_overif2:
		; move to next dot-pair and write val in X
		TYA 
		CLC
		ADC #8
		TAY
		LDA #$05
		JSR vdp_set_addr_w
		JSR vdp_writex

		RTS

;----------------------------------------------------------------------
; Sound
;
.ifdef SOUND
sound_vol:
		LDA br_c0_vol
		CMP #$0F
		BCS @over
		INC br_c0_vol
		LDA #%10010000 ; c0 vol
		ORA br_c0_vol
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
		STZ br_c0_vol
		RTS
sound_pong:
		; Set frequency to %0100000110 = 262 -> 3.6864MHz/32*262 ~= 440Hz
		LDA #%10000110  ; Freq Channel 1 (of 3)
		JSR snd_write
		LDA #%00010000  ; Freq DDDDDD 
		JSR snd_write
		LDA #%10010000 ; c0 vol = full (0)
		JSR snd_write
		STZ br_c0_vol
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

print_ball_xy:
;		ld16 R0, strbuf
;		lda ballx
;		jsr fmt_hex_string
;		jsr acia_puts
;		lda #' '
;		jsr acia_putc
;		ld16 R0, strbuf
;		lda bally
;		jsr fmt_hex_string
;		jsr acia_puts
;		jsr acia_put_newline
;		rts

quit_message:
	.byte "Goodbye!",$0d,$0a,$00
