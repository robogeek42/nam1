; vim: ts=4 et sw=4
; Pong 

.setcpu "65C02"

.include "../macros.inc65"
.include "../zeropage.inc65"
.include "../io.inc65"
.include "../video_vars.inc65"
.include "../video_registers.inc65"
.include "../colors.inc65"
.include "../scancodes.inc65"
;.include "../bcd.inc65"
.include "../firmware.symbols"

.export breakout
.export BOUT_IRQ

; breakout vars in basic program area
bout_vars = $7000

ballx	= bout_vars+0
bally	= bout_vars+1
ballxv	= bout_vars+4		; ball velocity in X
ballyv	= bout_vars+5		; ball velocity in Y
batx    = bout_vars+6		; left pos of bat

br_game		= bout_vars+8; Game state. 0=not started, 1=playing, 2=pause, FF=quit, FE=win message
IRQ_COUNT	= bout_vars+9
IRQ_OLD		= bout_vars+10 ; 2 bytes
ball_update	= bout_vars+12  ; number of 1/60sec intervals between updating ball
IRQ_EVENT   = bout_vars+13
ballnextx   = bout_vars+14
ballnexty   = bout_vars+15
wallbounce  = bout_vars+16  ; temp flag if bounced

br_c0_vol	= bout_vars+20;
strbuf2		= bout_vars+21;

BORDER_X_MIN = 4
BORDER_X_MAX = 122
BORDER_Y_MIN = 4
BORDER_Y_MAX = 90

BAT_LINE = 86       ; bat is on 88,89
BAT_LINE_DIV2 = 43  ; bat line in chars
BAT_WIDTH = 12
BAT_EDGE_SIZE = 2
START_BAT = 60

START_BALL_X = 62
START_BALL_Y = 84
START_BALL_VX = $02
START_BALL_VY = $FE

BALL_INITIAL_UPDATE_SPEED = 4

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
        ; load a custom colour in mode 2 ... 
        LDA #FG_WHITE | BG_BLACK
        STA VDP_MODE2_COL
		LDA #2					; Graphics II mode
		JSR vdp_set_mode

        JSR load_graphics

; Draw board
        JSR draw_board

;; initialise game variables
		STZ br_game

        JSR mb_starting_pos
		

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
        
        LDA #BALL_INITIAL_UPDATE_SPEED
        STA ball_update
		STZ IRQ_COUNT
		STZ IRQ_EVENT

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
        STZ IRQ_EVENT

.if .def(PS2K) || .def(VKEYB)
		JSR check_key_flags
.endif
		JSR draw_paddle

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
        LDA IRQ_COUNT
        CMP ball_update     ; ball update speed
        BCC gl_skip_update
        STZ IRQ_COUNT

		JSR clear_ball
		JSR move_ball
		JSR draw_ball2

		JSR check_game
		;JSR draw_score

gl_skip_update:
        JMP game_loop

;---------------------------------------
; Interrupt handler
BOUT_IRQ:
		PHA

		JSR vdp_getstatus		   ;; read VDP status to reenable the VDP interrupt
		INC IRQ_COUNT			   ;; count++
        INC IRQ_EVENT              ;; will be reset by client

		PLA
		RTI
;---------------------------------------


;---------------------------------------
; Get input from ACIA
get_input_serial:
        LDA ACIA_CTRL_STATUS
        AND #ACIA_STATUS_RDRF
        BEQ gi_done
        LDA ACIA_TX_RX

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
		CMP #4
		BCC giml_over
		STA batx
; debug
;JSR print_bat_x
;LDA #' '
;JSR acia_putc
;
	giml_over:
		RTS
gi_move_right:
		LDA batx
		INC
		CMP #113
		BCS gimr_over
		STA batx
; debug
;JSR print_bat_x
;LDA #' '
;JSR acia_putc
;
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
        lda KBD_FLAGS
		cpx #0
		beq @do_make
		and #$FE            ; key unpressed - unset bit 0
        sta KBD_FLAGS
		rts
  @do_make:
		ora #$01            ; key was pressed - set bit 0
        sta KBD_FLAGS
		rts

gip_do_LEFT:
		lda KBD_FLAGS
		cpx #0
		beq @do_make
		and #$FD
        sta KBD_FLAGS
		rts
  @do_make:
		ora #$02
        sta KBD_FLAGS
		rts

.endif

;---------------------------------------
; Check game conditions
check_game:
		RTS

;---------------------------------------
; Draw ball
draw_ball_set_address_y:
        LDA bally   ; calc bally/4 * 32 == bally * 8
        AND #$FC    ; /4 *4 gets rid of 2xlsb
        STA TMP0    ; store result in TMP0
        STZ TMP0+1

        ASL TMP0
        ROL TMP0+1
        ASL TMP0
        ROL TMP0+1
        ASL TMP0
        ROL TMP0+1
        RTS

draw_ball_set_address:
        JSR draw_ball_set_address_y
        LDA ballx
        LSR         ; 
        LSR         ; ballx/4
        STA TMP1
        add8To16 TMP1, TMP0

        JSR vdp_setaddr_name_table_offset_g2
        RTS
draw_ball_set_address_next_line:
        JSR draw_ball_set_address_y
        
        LDA ballx
        LSR         ; 
        LSR         ; ballx/4
        CLC
        ADC #32
        STA TMP1
        add8To16 TMP1, TMP0

        JSR vdp_setaddr_name_table_offset_g2
        RTS
        
draw_ball2:
        ; decide on char

        ; single char if x<3 and y<3
        ; 2 chars if x=3 or y=3
        ; 4 chars if x=3 and y=3

        ; get index into BALL tables
        LDA bally
        AND #3
        ASL
        ASL       
        STA TMP2+1  ; 4 x (bally % 4)

        LDA ballx
        AND #3
        STA TMP2    ; (ballx % 4)

        CLC
        ADC TMP2+1
        TAY         ; Y has index into ball chars table for each quadrant

        ; draw 1st quad
        JSR draw_ball_set_address
        LDA BALL_DATA_2pix_CHARS_quad_00, Y
        JSR vdp_write

        LDA TMP2            ; ball span 2 X ?
        CMP #3
        BNE db2_check_y     ; no
                            ; yes
        ; draw 2nd quad (X=1,Y=0)
        LDA BALL_DATA_2pix_CHARS_quad_10, Y
        JSR vdp_write
        
        ; can be here if X went across 2 chars or not
    db2_check_y:
        LDA bally          ; y span 2 Y?
        AND #3
        CMP #3
        BNE db2_end         ; no
                            ; yes
        ; draw 3rd quad
        JSR draw_ball_set_address_next_line
        LDA BALL_DATA_2pix_CHARS_quad_01, Y
        JSR vdp_write

        LDA TMP2            ; ball span 2 X ?
        CMP #3
        BNE db2_end         ; no
        
        ; draw 4th quad
        LDA BALL_DATA_2pix_CHARS_quad_11, Y
        JSR vdp_write

    db2_end:
        RTS

;---------------------------------------
; Clear ball
clear_ball:
        ; always clear 1st quad
        JSR draw_ball_set_address
        LDA #GR_SPACE
        JSR vdp_write

        LDA ballx   ; check X
        AND #3
        CMP #3
        BNE cb_check_y

        ; clear 2nd quad 
        LDA #GR_SPACE
        JSR vdp_write

    cb_check_y:
        LDA bally          ; y span 2 Y?
        AND #3
        CMP #3
        BNE cb_end         ; no

        ; clear 3rd quad 
        JSR draw_ball_set_address_next_line
        LDA #GR_SPACE
        JSR vdp_write

        LDA ballx   ; check X again
        AND #3
        CMP #3
        BNE cb_end

        ; clear 4th quad 
        LDA #GR_SPACE
        JSR vdp_write

    cb_end:
		RTS
		
;--------------------------------------------------
; Lost ball. Reset ball and bat and pause game
mb_lost_ball:
        LDA #2
        STA br_game

mb_starting_pos:
	; starting bat position
		LDA #START_BAT
		STA batx
	; starting ball position and speed
		LDA #START_BALL_X 
		STA ballx
		LDA #START_BALL_Y 
		STA bally
		LDA #START_BALL_VX
		STA ballxv
		LDA #START_BALL_VY
		STA ballyv
        RTS
;--------------------------------------------------
; Check ball position and change speed as necessary
; Move the ball according to current speed
;      -- ballnextx/y contains next position.
;      -- if next pos is next to wall, change direction
;
move_ball:
        STZ wallbounce
; 1. Check walls
;    Add XV to X -> nextx
		CLC	
		LDA ballxv
		ADC ballx
		STA ballnextx

;    IF at border reverse XV
        LDX #BORDER_X_MIN
		CMP #BORDER_X_MIN
		BCC mb_reverse_xv
        LDX #BORDER_X_MAX
		CMP #BORDER_X_MAX
		BCS mb_reverse_xv
		JMP mb_do_y
	mb_reverse_xv:
		LDA ballxv
		TWOSCOMP				; 2s complement
		STA ballxv
    ; next x should be adjusted to account for bounce
    ; formula is 2 x wallX-nextX
        TXA
        ASL
        SEC
        SBC ballnextx
        STA ballnextx
        INC wallbounce
	
;    Add YV to Y -> nexty
mb_do_y:
		CLC
		LDA ballyv
		ADC bally
		STA ballnexty
		
; 2. IF Y at bot edge go to pause state and reset ball and bar
		CMP #BORDER_Y_MAX
		BCS mb_lost_ball		; 
		CMP #BORDER_Y_MIN
		BMI mb_reverse_yv		; Y Top edge
		JMP mb_check_if_bounced
	mb_reverse_yv:
		LDA ballyv
		TWOSCOMP
		STA ballyv
    ; next Y should be adjusted to account for bounce
    ; formula is 2 x topY-nextY
        LDA #BORDER_Y_MIN
        ASL
        SEC
        SBC ballnexty
        STA ballnexty
        INC wallbounce

; 3 If bounced at a wall, update position and go back to start 
mb_check_if_bounced:
        LDA wallbounce
        CMP #0
        BEQ mb_hit_bat_check
    ; resolve
        JMP mb_check_brick
		;LDA ballnextx
		;STA ballx				; store new X
		;LDA ballnexty
		;STA bally				; store new Y
        ;JMP move_ball

; at this point, wall bounces are resolved and next position is either
;  - possible bounce off bat
;  - possible hit of brick
;  - nothing to hit

; 4. Check bat first
mb_hit_bat_check:
        ; Is nextY on the same line as the bat?
        LDA ballnexty  
        LSR
        CMP #BAT_LINE_DIV2      ; can only hit bat on one line
        BNE mb_check_brick

; debug
;JSR acia_put_newline
JSR print_bat_x
LDA #' ' 
JSR acia_putc
JSR print_ball_xy
JSR acia_put_newline
        
        LDA ballnextx                ; next ball x
        CMP batx                ; Bat leftmost pos
        BCC jmp_mb_store_final  ; ballx < batx
        CLC
        LDA batx
        ADC #BAT_WIDTH 
        CMP ballnextx
        BCC jmp_mb_store_final  ; batx+12 < ballx
        ; reverse Y dir
		LDA ballyv
		TWOSCOMP
		STA ballyv
    ; next Y should be adjusted to account for bounce
    ; formula is 2 x batY-nextY
        LDA #BAT_LINE
        ASL
        SEC
        SBC ballnexty
        STA ballnexty

    ; change x speed if hit left edge of bat
        LDA ballnextx                ; next ball x
        SEC
        SBC batx
        CMP #BAT_EDGE_SIZE                ; Bat leftmost 2 pixels
        BCC mb_hit_left_part  ; ballx-batx < 2
        CMP #BAT_WIDTH-BAT_EDGE_SIZE      ; bat rightmost 2 pixels
        BCS mb_hit_right_part ; ballx-batx >= 10
        ; can't hit bricks from here so we are done
jmp_mb_store_final:
        JMP mb_store_final

    mb_hit_left_part:
        ; hit left part, make speed more left (subtract 1)
        SEC
        LDA ballxv
        SBC #1
        STA ballxv
; debug
JSR print_ball_speed
JSR acia_put_newline

        JMP mb_store_final

    mb_hit_right_part:
        ; hit right part, increase speed to right
        CLC
        LDA ballxv
        ADC #1
        STA ballxv
; debug
JSR print_ball_speed
JSR acia_put_newline
        JMP mb_store_final

; 5. Check bricks. We still have nextX/Y in ballnextx/y
mb_check_brick:
        ; only check if Y < 28
        LDA ballnexty  ; next ballY
        CMP #28
        BCS mb_store_final ; no chance of hitting bricks so resolve and exit

        ; calc ball pos in name table
        JSR get_NT_read_addr_for_ballnext
        JSR vdp_read
        CMP #0              
        BEQ mb_store_final  ; char == 0 is a space. Resolve and exit.

; debug 
ld16 R0, strbuf2
jsr fmt_hex_string
jsr acia_puts
jsr acia_put_newline

;jmp mb_store_final

        ; Hit. set NT at this pos blank
        ;JSR draw_ball_set_address_y
        ;LDA #GR_SPACE
        ;JSR vdp_write
        ; bounce
		LDA ballyv
		TWOSCOMP
		STA ballyv
        ; subtract y
        LDA ballnexty
        CLC
        ADC ballyv
        STA ballnexty

; 6. Resolve next x/y 
mb_store_final:
		; change is good, save into ball position
		LDA ballnextx
		STA ballx				; store new X
		LDA ballnexty
		STA bally				; store new Y

        RTS

;--------------------------------------------------
get_NT_read_addr_for_ballnext:
        LDA ballnexty   ; calc bally/4 * 32 == bally * 8
        AND #$FC    ; /4 *4 gets rid of 2xlsb
        STA TMP0    ; store result in TMP0
        STZ TMP0+1

        ASL TMP0
        ROL TMP0+1
        ASL TMP0
        ROL TMP0+1
        ASL TMP0
        ROL TMP0+1
        LDA ballnextx
        LSR         ; 
        LSR         ; ballx/4
        STA TMP1
        add8To16 TMP1, TMP0

; debug
ld16 R0, strbuf2
LDA TMP0
STA ZP_TMP0
LDA TMP0+1
STA ZP_TMP0+1
jsr fmt_hex_string
jsr acia_puts
LDA ZP_TMP0
jsr fmt_hex_string
jsr acia_puts
lda #' '
jsr acia_putc
LDA ZP_TMP0
STA TMP0
LDA ZP_TMP0+1
STA TMP0+1

        JSR vdp_setaddr_name_table_offset_g2_read
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
; load custom graphics chars 
;
load_graphics:

        STZ TMP0    ; page counter - $00, $08, $10 

        ; outer look is to load 3 pages
lg_loop_out:
        ld16 TMP1, GRAPHICS_TAB  
        ; set VDP load address
        JSR vdp_setaddr_pattern_table_offset

        LDX #NUM_GRAPH_CHARS    ; max 256 characters (2k bytes)
lg_char_loop:
        LDY #0
lg_byte_loop:
        LDA (TMP1), Y
        JSR vdp_write
        INY
        CPY #8
        BNE lg_byte_loop
        add8To16 #8, TMP1
        DEX
        BNE lg_char_loop

        ; Mode2 GRII screen has 768 patterns = 6k
        ; do next set of 256 chars (2048 bytes = $800)
        LDA TMP0
        CLC
        ADC #$08
        STA TMP0
        CMP #$18
        BNE lg_loop_out

; colours for bricks
        LDA #$80
        STA TMP0
        LDA #$01
        STA TMP0+1
        JSR vdp_setaddr_color_table_offset_g2
        LDA #FG_DRK_BLUE | BG_BLACK
        JSR lg_set_cols
        LDA #FG_MED_RED | BG_BLACK
        JSR lg_set_cols
        LDA #FG_MED_GREEN | BG_BLACK
        JSR lg_set_cols
        LDA #FG_MAGENTA | BG_BLACK
        JSR lg_set_cols
        RTS

lg_set_cols:
        LDX #24
    lgsc_loop:
        JSR vdp_write
        DEX
        BNE lgsc_loop
        RTS

;----------------------------------------------------------------------
; Draw board
;

draw_board:

        ; Name Table (characters first)
        STZ TMP0
        STZ TMP0+1
        JSR vdp_setaddr_name_table_offset_g2
        ; TMP1 points to row index
        ; X points to char in row at that index
        STZ TMP1
@db_loop2:        
        LDX TMP1            ; row index
        LDA SCR_ROW_INDEX,X
        ASL                 ; Index * 32
        ASL
        ASL
        ASL
        ASL
        TAY                 ; row at index TMP1 is in Y
        LDX #32
@db_loop1:
        LDA SCR_ROWS,Y      ; get char at Y
        JSR vdp_write
        INY
        DEX
        BNE @db_loop1
        INC TMP1
        LDA TMP1
        CMP #24
        BNE @db_loop2

		RTS

;----------------------------------------------------------------------
; Draw paddle - width 12 pixels (3 chars)
draw_paddle:
        ; clear
        JSR clear_paddle_line

        ; bat on line 22 = 22*32 = $2C0
        LDA #$C0
        STA TMP0
        LDA #$02
        STA TMP0+1
        LDA batx
        LSR         ;
        LSR         ; div by 4
        STA TMP1
        add8To16 TMP1, TMP0
        JSR vdp_setaddr_name_table_offset_g2
        LDA batx
        AND #3
        CMP #0
        BEQ dp_left
        TAX
        LDA BAT_DATA_CHARS_LEFT,X
        JSR vdp_write
        LDA #BAT_FULL
        JSR vdp_write
        LDA #BAT_FULL
        JSR vdp_write
        LDA BAT_DATA_CHARS_RIGHT,X
        JSR vdp_write
		RTS
dp_left:
        LDA #BAT_FULL
        JSR vdp_write
        LDA #BAT_FULL
        JSR vdp_write
        LDA #BAT_FULL
        JSR vdp_write
        RTS

clear_paddle_line:
        LDA #$02
        STA TMP0+1
        LDA #$C0
        STA TMP0
        JSR vdp_setaddr_name_table_offset_g2
        LDY #32 ; second line-type in board table
        LDX #32 ; write 32 chars as a line
@dbl_loop1:
        LDA SCR_ROWS,Y      ; get char at Y
        JSR vdp_write
        INY
        DEX
        BNE @dbl_loop1
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
		lda ballx
        JSR BINBCD8                ; convert to BCD and write in RES,RES+1
		ld16 R0, strbuf2
        JSR BCD2STR                ; convert BCD to string
		jsr acia_puts
		lda #','
		jsr acia_putc

		lda bally
        JSR BINBCD8                ; convert to BCD and write in RES,RES+1
		ld16 R0, strbuf2
        JSR BCD2STR                ; convert BCD to string
		jsr acia_puts
		;jsr acia_put_newline
		rts
print_bat_x:
		lda batx
        JSR BINBCD8                ; convert to BCD and write in RES,RES+1
		ld16 R0, strbuf2
        JSR BCD2STR                ; convert BCD to string
		jsr acia_puts
        rts
print_ball_speed:
		lda #'s'
		jsr acia_putc
		lda #':'
		jsr acia_putc
		lda ballxv
        JSR BINBCD8                ; convert to BCD and write in RES,RES+1
		ld16 R0, strbuf2
        JSR BCD2STR                ; convert BCD to string
		jsr acia_puts
		lda #','
		jsr acia_putc

		lda ballyv
        JSR BINBCD8                ; convert to BCD and write in RES,RES+1
		ld16 R0, strbuf2
        JSR BCD2STR                ; convert BCD to string
		jsr acia_puts
		;jsr acia_put_newline
		rts

quit_message:
	.byte "Goodbye!",$0d,$0a,$00


SCR_ROW_INDEX:
    .byte $00,$01,$03,$04,$05,$06,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$02
SCR_ROWS:
    .byte $16,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$15
    .byte $04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03
    .byte $14,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$13
; all col1
    .byte $04,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$31,$32,$03
; all col2
    .byte $04,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$34,$35,$03
; all col3
    .byte $04,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$37,$38,$03
; all col4
    .byte $04,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$3A,$3B,$03
SCR_ROW_COLOURS:
    .byte $F0,$F0,$30,$40,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0

BAT_DATA_CHARS_LEFT:
    .byte BAT_FULL,BAT_R3,BAT_R2,BAT_R1
BAT_DATA_CHARS_RIGHT:
    .byte GR_SPACE,BAT_L1,BAT_L2,BAT_L3
BALL_DATA_CHARS:
    .byte $13,$14,$15,$16

BALL_DATA_2pix_CHARS_quad_00:
    ; Y=0 X=0   1   2   3 Y=1 X=0  1   2    3 Y=2 X=0   1   2   3 Y=3 X=0   1   2   3
    .byte $1D,$1E,$1F,$20,    $22,$23,$24,$25,    $27,$28,$29,$2A,    $2C,$2D,$2E,$2F
BALL_DATA_2pix_CHARS_quad_10:
    ; Y=0 X=0   1   2   3 Y=1 X=0   1   2   3 Y=2 X=0   1   2   3 Y=3 X=0   1   2   3
    .byte $00,$00,$00,$1C,    $00,$00,$00,$21,    $00,$00,$00,$26,    $00,$00,$00,$2B
BALL_DATA_2pix_CHARS_quad_01:
    ; Y=0 X=0   1   2   3 Y=1 X=0  1   2   3 Y=2 X=0   1   2   3 Y=3 X=0   1   2   3
    .byte $00,$00,$00,$00,    $00,$00,$00,$00,   $00,$00,$00,$00,     $18,$19,$1A,$1B
BALL_DATA_2pix_CHARS_quad_11:
    ; Y=0 X=0   1   2   3 Y=1 X=0  1   2   3 Y=2 X=0   1   2   3 Y=3 X=0   1   2   3
    .byte $00,$00,$00,$00,    $00,$00,$00,$00,   $00,$00,$00,$00,     $00,$00,$00,$17

NUM_GRAPH_CHARS = $3C

GRAPHICS_TAB:
    GR_SPACE = 0
    .byte $00,$00,$00,$00,$00,$00,$00,$00   ; space
    GR_HALF_TOP = 1
    .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00   ; top half
    GR_HALF_BOT = 2
    .byte $00,$00,$00,$00,$FF,$FF,$FF,$FF   ; bot half
    GR_HALF_LEFT = 3
    .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0   ; left half
    GR_HALF_RIGHT = 4
    .byte $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F   ; right half
    GR_HALF_TOP_LEFT = 5
    .byte $FF,$FF,$FF,$FF,$F0,$F0,$F0,$F0   ; top and left
    GR_HALF_TOP_RIGHT = 6
    .byte $FF,$FF,$FF,$FF,$0F,$0F,$0F,$0F   ; top and right
    GR_HALF_BOT_LEFT = 7
    .byte $F0,$F0,$F0,$F0,$FF,$FF,$FF,$FF   ; bot and left
    GR_HALF_BOT_RIGHT = 8
    .byte $0F,$0F,$0F,$0F,$FF,$FF,$FF,$FF   ; bot and right
    GR_HALF_MID = 9
    .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00   ; simple brick all to edges
    GR_HALF_BRICK_LEFT = $A
    .byte $00,$7F,$7F,$7F,$7F,$7F,$7F,$00   ; brick left part
    GR_HALF_BRICK_RIGHT = $B
    .byte $00,$FE,$FE,$FE,$FE,$FE,$FE,$00   ; brick right part

BAT_DATA:
    BAT_FULL = $0C
    .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00   ; full bat
    BAT_R3 = $0D
    .byte $3F,$3F,$3F,$3F,$00,$00,$00,$00   ; 3 quarter at right
    BAT_R2 = $0E
    .byte $0F,$0F,$0F,$0F,$00,$00,$00,$00   ; half at right
    BAT_R1 = $0F
    .byte $03,$03,$03,$03,$00,$00,$00,$00   ; quarter at right
    BAT_L1 = $10
    .byte $C0,$C0,$C0,$C0,$00,$00,$00,$00   ; quarter at left
    BAT_L2 = $11
    .byte $F0,$F0,$F0,$F0,$00,$00,$00,$00   ; half at left
    BAT_L3 = $12
    .byte $FC,$FC,$FC,$FC,$00,$00,$00,$00   ; 3 quarter at left
     
BALL_DATA:
    ; 4x4 blocks by quadrant
    BALL_TL = $13
    .byte $F0,$F0,$F0,$F0,$00,$00,$00,$00   ; T L
    BALL_TR = $14
    .byte $0F,$0F,$0F,$0F,$00,$00,$00,$00   ; T R
    BALL_BL = $15
    .byte $00,$00,$00,$00,$F0,$F0,$F0,$F0   ; B L
    BALL_BR = $16
    .byte $00,$00,$00,$00,$0F,$0F,$0F,$0F   ; B R

BALL_DATA_2pix:
    ; $17
    .byte $C0,$C0,$00,$00,$00,$00,$00,$00
    .byte $F0,$F0,$00,$00,$00,$00,$00,$00
    .byte $3C,$3C,$00,$00,$00,$00,$00,$00
    .byte $0F,$0F,$00,$00,$00,$00,$00,$00
    .byte $03,$03,$00,$00,$00,$00,$00,$00
    ; $1C
    .byte $C0,$C0,$C0,$C0,$00,$00,$00,$00
    .byte $F0,$F0,$F0,$F0,$00,$00,$00,$00
    .byte $3C,$3C,$3C,$3C,$00,$00,$00,$00
    .byte $0F,$0F,$0F,$0F,$00,$00,$00,$00
    .byte $03,$03,$03,$03,$00,$00,$00,$00
    ; $21
    .byte $00,$00,$C0,$C0,$C0,$C0,$00,$00
    .byte $00,$00,$F0,$F0,$F0,$F0,$00,$00
    .byte $00,$00,$3C,$3C,$3C,$3C,$00,$00
    .byte $00,$00,$0F,$0F,$0F,$0F,$00,$00
    .byte $00,$00,$03,$03,$03,$03,$00,$00
    ; $26
    .byte $00,$00,$00,$00,$C0,$C0,$C0,$C0
    .byte $00,$00,$00,$00,$F0,$F0,$F0,$F0
    .byte $00,$00,$00,$00,$3C,$3C,$3C,$3C
    .byte $00,$00,$00,$00,$0F,$0F,$0F,$0F
    .byte $00,$00,$00,$00,$03,$03,$03,$03
    ; $2B
    .byte $00,$00,$00,$00,$00,$00,$C0,$C0
    .byte $00,$00,$00,$00,$00,$00,$F0,$F0
    .byte $00,$00,$00,$00,$00,$00,$3C,$3C
    .byte $00,$00,$00,$00,$00,$00,$0F,$0F
    .byte $00,$00,$00,$00,$00,$00,$03,$03

BRICK_COLOUR:
    ; $30
    .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00   ; simple brick all to edges
    .byte $00,$7F,$7F,$7F,$7F,$7F,$7F,$00   ; brick left part
    .byte $00,$FE,$FE,$FE,$FE,$FE,$FE,$00   ; brick right part

    .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00   ; simple brick all to edges
    .byte $00,$7F,$7F,$7F,$7F,$7F,$7F,$00   ; brick left part
    .byte $00,$FE,$FE,$FE,$FE,$FE,$FE,$00   ; brick right part

    .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00   ; simple brick all to edges
    .byte $00,$7F,$7F,$7F,$7F,$7F,$7F,$00   ; brick left part
    .byte $00,$FE,$FE,$FE,$FE,$FE,$FE,$00   ; brick right part

    .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00   ; simple brick all to edges
    .byte $00,$7F,$7F,$7F,$7F,$7F,$7F,$00   ; brick left part
    .byte $00,$FE,$FE,$FE,$FE,$FE,$FE,$00   ; brick right part
