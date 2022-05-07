; vim: ts=4 sw=4
; pacman - draw map

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
.include "scancodes.inc65"
.include "pckybd.inc65"
.include "colors.inc65"

.export pacman

; pacman vars in basic program area
pm_vars = $7000

; game state 0 = not started 1 = playing  FF =  quit
pm_game = pm_vars + 0
pm_input_dir = pm_vars + 1

; positions (x,y) and direction for each actor
pm_info = pm_vars + 2

; PACMAN position info
PM_POS_X	= pm_info+0	  ; X/Y in screen characters
PM_POS_Y	= pm_info+1
PM_DIR		= pm_info+2   ; Direction (number)
PM_NT_LO	= pm_info+3   ; map (name table) position
PM_NT_HI	= pm_info+4   ; map (name table) position
PM_ALLOWED	= pm_info+5   ; bitmask of allowed directions

g1_info		= pm_info+8		; exact 8 between all data sections
; Ghost 1
G1_X		= g1_info+0
G1_Y		= g1_info+1
G1_DIR		= g1_info+2   ; Direction
G1_NT_LO	= g1_info+3
G1_NT_HI	= g1_info+4
G1_ALLOWED	= g1_info+5
G1_MODE		= g1_info+6   ; Mode (0=norm 1=scared)

g2_info		= g1_info+8
; Ghost 2
G2_X		= g2_info+0
G2_Y		= g2_info+1
G2_DIR		= g2_info+2   ; Direction
G2_NT_LO	= g2_info+3
G2_NT_HI	= g2_info+4
G2_ALLOWED	= g2_info+5
G2_MODE		= g2_info+6   ; Mode (0=norm 1=scared)

g3_info		= g2_info+8
; Ghost 3
G3_X		= g3_info+0
G3_Y		= g3_info+1
G3_DIR		= g3_info+2   ; Direction
G3_NT_LO	= g3_info+3
G3_NT_HI	= g3_info+4
G3_ALLOWED	= g3_info+5
G3_MODE		= g3_info+6   ; Mode (0=norm 1=scared)

; only 3 for now ...
pm_positions_end = g3_info+7

; sprite data table, 4 bytes per sprite
; Y, X, Pattern No, Color/EarlyFlag
; starts with number of sprites enabled

pm_sprite_table = pm_positions_end+0

PM_NUMPRITES = pm_sprite_table+0

PM_ST_SPR1_Y = pm_sprite_table+1	; (19)
PM_ST_SPR1_X = pm_sprite_table+2
PM_ST_SPR1_P = pm_sprite_table+3
PM_ST_SPR1_C = pm_sprite_table+4

PM_ST_SPR2_Y = pm_sprite_table+5
PM_ST_SPR2_X = pm_sprite_table+6
PM_ST_SPR2_P = pm_sprite_table+7
PM_ST_SPR2_C = pm_sprite_table+8

PM_ST_SPR3_Y = pm_sprite_table+9
PM_ST_SPR3_X = pm_sprite_table+10
PM_ST_SPR3_P = pm_sprite_table+11
PM_ST_SPR3_C = pm_sprite_table+12

PM_ST_SPR4_Y = pm_sprite_table+13
PM_ST_SPR4_X = pm_sprite_table+14
PM_ST_SPR4_P = pm_sprite_table+15
PM_ST_SPR4_C = pm_sprite_table+16

PM_ST_SPR5_Y = pm_sprite_table+17
PM_ST_SPR5_X = pm_sprite_table+18
PM_ST_SPR5_P = pm_sprite_table+19
PM_ST_SPR5_C = pm_sprite_table+20

pm_local =  pm_sprite_table+21

IRQ_OLD			= pm_local+0  ; 2 bytes
PM_IRQCOUNT		= pm_local+2
PM_INTERRUPT	= pm_local+3
GHOST_IRQCOUNT	= pm_local+4
UPDATE_FLAG		= pm_local+5  ; flag 1 = update sprites
PM_SCORE		= pm_local+6  ; 2 bytes
PM_STR_BUFFER	= pm_local+8  ; 12 bytes

; IRQ location - points to address part of JMP xxxx
IRQ_ADDR = $20A

.code

;------------------------------------------------------------------
; 1. Load chars to consecutive locations in 
; MODE 2 pattern table
;
pm_loadchars:
			ld16 TMP0,PM_CHAR_TAB	   ; character defs
pmdm_loop2: LDY #0
pmdm_loop1: LDA (TMP0),Y
			JSR vdp_write
			INY
			BNE pmdm_loop1			  ; loop 256 times = 32 8byte chars
			RTS
pacman:
pm_drawmaze:
			phx
			phy
			LDA #2					  ; MODE 2
			JSR vdp_set_mode
			LDA #$F0
			JSR vdp_set_base_colors

			JSR vdp_setaddr_pattern_table
			JSR pm_loadchars

			; load chars twice more
			LDA #$08
			STA TMP0
			JSR vdp_setaddr_pattern_table_offset
			JSR pm_loadchars

			LDA #$10
			STA TMP0
			JSR vdp_setaddr_pattern_table_offset
			JSR pm_loadchars

;------------------------------------------------------------------
; 2. Colours - Blue for maze, yellow for pills & dots
pm_loadcols:
			LDA #3
			STA TMP0+1

			LDA VDP_REGS+3	  ;; Color table
			AND #$80			;; just want upper bit
			CLC
			ROR
			ROR
			STA TMP0			; TMP 0 has msb of color table
pmdm_colloop:
			LDY #0
			LDA TMP0
			JSR vdp_set_addr_w

			LDA #$40					; Blue/black
			LDX #28					 ; 28 characters
pmdm_loop4: LDY #8					  ; 8 bytes per char
pmdm_loop3: JSR vdp_write
			DEY
			BNE pmdm_loop3
			DEX
			BNE pmdm_loop4

			LDA #$90					; Yellow/black
			LDX #4					  ; 4 characters
pmdm_loop6: LDY #8					  ; 8 bytes per char
pmdm_loop5: JSR vdp_write
			DEY
			BNE pmdm_loop5
			DEX
			BNE pmdm_loop6
		 
			CLC						 ; Add 2048 to address (8 to hi)
			LDA TMP0
			ADC #$08
			STA TMP0

			DEC TMP0+1				  ; we do the colour load 3 times
			LDA TMP0+1
			BNE pmdm_colloop

;------------------------------------------------------------------
; 3. Load pattern to name table
;	Screen is 32x24 characters
pm_loadnames:
			JSR vdp_setaddr_name_table
			ld16 TMP0, PACMAN_MAZE
			LDX #24
pmdm_loop8: LDY #0 
pmdm_loop7: LDA (TMP0),Y
			JSR vdp_write
			INY
			CPY #32					 ; 32 chars per line
			BNE pmdm_loop7
			add8To16 #32, TMP0
			DEX
			BNE pmdm_loop8
;------------------------------------------------------------------
; 4. Load game map 32x24
;			ld16 TMP2, pm_map		   ; set address of internal map
;			ld16 TMP0, PACMAN_MAP	   ; 
;			LDX #3					  ; 3 * 256
;pmdm_loop10: LDY #0 
;pmdm_loop9: LDA (TMP0),Y
;			STA (TMP2),Y
;			INY
;			BNE pmdm_loop9
;			add8To16 #32, TMP0
;			add8To16 #32, TMP2
;			DEX
;			BNE pmdm_loop10

;------------------------------------------------------------------
; 5. Sprites
; Init and Set sprite type (8x8 unmag)
			JSR vdp_init_sprites
			JSR spr_set_small
			JSR spr_set_mag_off

; Load sprite patterns
			ld16 ZP_TMP0, PM_SPRITES
			STZ ZP_TMP2				; load into P=0,1 ...
@next_pattern:
			JSR vdp_load_sprite_data_from_mem
			CLC
			add8To16 #8,ZP_TMP0		; move data ptr to next pattern
			INC ZP_TMP2				; inrement pattern numner
			LDA ZP_TMP2
			CMP #PM_NUM_SPRITE_PATTERNS
			BNE @next_pattern

; Initialise sprite table
			; Pacman
			LDA #112
			STA PM_ST_SPR1_X
			LDA #144
			STA PM_ST_SPR1_Y
			LDA #0
			STA PM_ST_SPR1_P
			LDA #LIT_YELLOW
			STA PM_ST_SPR1_C

			; Red Ghost
			LDA #96
			STA PM_ST_SPR2_X
			LDA #88
			STA PM_ST_SPR2_Y
			LDA #9
			STA PM_ST_SPR2_P
			LDA #DRK_RED
			STA PM_ST_SPR2_C

			; Green Ghost
			LDA #112
			STA PM_ST_SPR3_X
			LDA #88
			STA PM_ST_SPR3_Y
			LDA #9
			STA PM_ST_SPR3_P
			LDA #LIT_GREEN
			STA PM_ST_SPR3_C

			; Cyan Ghost
			LDA #128
			STA PM_ST_SPR4_X
			LDA #88
			STA PM_ST_SPR4_Y
			LDA #9
			STA PM_ST_SPR4_P
			LDA #CYAN
			STA PM_ST_SPR4_C

			LDA #4
			STA PM_NUMPRITES

; Initialise Positon data
; start at (14,18) = (14+18*32)=590=$24E
			LDA #$4E
			STA PM_NT_LO
			LDA #$02
			STA PM_NT_HI
			LDA #PM_DIR_L			  ; facing left
			STA PM_DIR
			JSR calc_pm_pos

; Enable sprites
			LDA PM_NUMPRITES		   ; enable sprites
			STA ZP_TMP0				; Pass number of sprites in ZP_TMP0
			JSR vdp_enable_sprites

;------------------------------------------------------------------
; 6. General setup
; write score
			STZ PM_SCORE
			STZ PM_SCORE+1
			JSR pm_draw_score

.if .def(PS2K) || .def(VKEYB)
; init keyboard
			jsr KBINIT
			lda #0
			sta KBD_FLAGS ; use KBD_FLAGS zp var to hold key flags
						  ; 7  6  5  4  3  2  1  0
						  ;			 a  s  d  w
.endif

;------------------------------------------------------------------
; 7. Interrupts
;
; Setup interrupt handler
pmih_save_old:
			LDA IRQ_ADDR
			STA IRQ_OLD
			LDA IRQ_ADDR+1
			STA IRQ_OLD+1

			LDA #$00
			STA PM_IRQCOUNT
			STA GHOST_IRQCOUNT

			LDA #<PM_IRQ
			STA IRQ_ADDR
			LDA #>PM_IRQ
			STA IRQ_ADDR+1

; Enable VDP IRQ output (every 1/60th second)
			LDA VDP_REGS+1		;; data to write is existing Reg1 (was set by MODE command)
			ORA #$20			;; with bit2 set - actually bit 5 if numbered from LSb like sensible chips
			STA VDP_REGS+1
			LDY #$81			;; register to write (1)
			JSR vdp_regwrite

			JSR vdp_getstatus   ;; clear interrupt flag in VDP

; Start allowing interrupts at CPU
			CLI

			STZ pm_game			; start at state 0 - not playing yet
			JSR get_pm_allowed	; get allowed directions

;------------------------------------------------------------------
; GAME LOOP
;   -- Busy loop waiting for interrupt to occur
;   -- On Interrupt:
;	  -- Get KBD Input - this sets flags of which keys are currently pressed
;	  -- Read the map and set allowed directions PM can move in
;	  -- Process the key presses into movement
;	  
game_loop:
gl_dogame:
			LDA PM_INTERRUPT		; check interrupt has happened
			BNE gl_get_input
			JMP game_loop

gl_get_input:
			LDA #0
			STA PM_INTERRUPT		; reset interrupt flag

			JSR pm_get_input_serial
.ifdef KEYB
			JSR pm_get_input_keyboard
.endif
.if .def(PS2K) || .def(VKEYB)
			JSR pm_get_input_ps2k
.endif
			JSR get_pm_allowed
			LDA #0
			JSR get_ghost_allowed

			JSR pm_process_input

			LDA pm_game		; check game state:
			CMP #$00		; 	game not started?
			BEQ game_loop	; 		yes, keep just checking input
			CMP #$FF		; 	quit requested?
			BNE gl_do_update	; 		no, then continue
			JMP quit_game	; 		yes, quit

gl_do_update:
			; Move the pacman position (PM_NT_LO/HI and sprite pos) 
			; based on PM_DIR and sprite pos
			JSR move_pacman
			JSR move_ghosts

			; check if is in square
			LDA PM_DIR				; check depends on direction of movement U/D or L/R
			CMP #PM_DIR_D			 ;
			BCS gl_check_vert		 ; >= Down = Down/Up

			LDA PM_ST_SPR1_X
			AND #$04				; 0-3, in square, 4-7 in square to right
			BNE gl_update_pm		; not in square
			BRA gl_do_insquare

gl_check_vert:
			LDA PM_ST_SPR1_Y
			AND #$04				; 0-3, in square, 4-7 in square below
			BNE gl_update_pm		; not in square
			
gl_do_insquare:
			JSR pm_read_nametable
			CMP #28				 ; 28 = dot
			BEQ gl_is_dot
			CMP #29
			BEQ gl_is_pill
			
			JMP gl_update_pm

gl_is_dot:
			; dot = add 10 to score
			add8To16 #10, PM_SCORE
			JMP gl_update_score
			
gl_is_pill:
			; pill = add 50 to score
			add8To16 #50, PM_SCORE

gl_update_score:
			; display new score
			JSR pm_draw_score

			; write to name table - space
			JSR pm_write_nametable

gl_update_pm:
			; update the sprite animations based on PM_DIR and tick number
			JSR pm_update_pm_sprite
			JSR pm_update_ghost_sprite

			LDA #1
			STA UPDATE_FLAG	   ; tell update routine to update sprites

			JMP game_loop

;------------------------------------------------------------------
; Exit
quit_game:
			JSR pm_quit_game
			ply
			plx
			RTS

;==================================================================
; Subroutines

;------------------------------------------------------------------
; move pacman based on 
;  - PM_DIR - (num 0=R,1=L,2=D,3=U) Current dir of movement
;  - PM_ST_SPR1_X/Y - to determine "In-square"
;  - PM_ALLOWED - (bitmask) allowed move directions
;  Updates 
;  - PM_NT_LO/HI	- new nametable pos
;  - PM_ST_SPR1_X/Y	- new sprite pos
;
move_pacman:
			LDA PM_IRQCOUNT				 ; update every N ticks
			AND #$01						; N=2 
			BNE mp_done
			LDA PM_DIR
			CMP #PM_DIR_R
			BEQ pm_move_right
			CMP #PM_DIR_L
			BEQ pm_move_left
			CMP #PM_DIR_U
			BEQ pm_move_up
			CMP #PM_DIR_D
			BEQ pm_move_down
mp_done:
			RTS

pm_move_left:
			; if pos is at left of current square then move
			; to next square of pos. Otherwise just move
			LDA PM_ST_SPR1_X
			AND #$07
			BNE pml_decx		 ; not 0 (fully in square) so keep moving

			; check allowed directions
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_L_BIT
			BEQ pml_skipx

			; decrement PM pos (absolute)
			dec16 PM_NT_LO
	pml_decx:
			DEC PM_ST_SPR1_X
	pml_skipx:
			RTS

pm_move_right:
			; if pos is at far right of current square then move
			; to next square of pos. Otherwise just move
			LDA PM_ST_SPR1_X
			AND #$07
			CMP #$07
			BNE pml_incx		 ; not 7 so keep moving

			; check allowed directions
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_R_BIT
			BEQ pml_skipx

			; increment PM pos (absolute)
			inc16 PM_NT_LO
			INC PM_ST_SPR1_X
			RTS
	pml_incx:
			; check allowed directions
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_R_BIT
			BEQ pml_skipx
			INC PM_ST_SPR1_X
			RTS

pm_move_up:
			; if pos is at top of current square then move
			; to next square of pos. Otherwise just move
			LDA PM_ST_SPR1_Y
			AND #$07
			BNE pml_decy		 ; not 0 (fully in square) so keep moving

			; check allowed directions
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_U_BIT
			BEQ pml_skipy

			; subtract 32 from PM pos (absolute)
			sub8From16 #32, PM_NT_LO
	pml_decy:
			DEC PM_ST_SPR1_Y
	pml_skipy:
			RTS

pm_move_down:
			; if pos is at bottom right of current square then move
			; to next square of pos. Otherwise just move
			LDA PM_ST_SPR1_Y
			AND #$07
			CMP #$07
			BNE pml_incy		 ; not 7 so keep moving

			; check allowed directions
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_D_BIT
			BEQ pml_skipy

			; add 32 to PM pos (absolute)
			add8To16 #32, PM_NT_LO
			INC PM_ST_SPR1_Y
			RTS
	pml_incy:
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_D_BIT
			BEQ pml_skipy
			INC PM_ST_SPR1_Y
			RTS
 
;---------------------------------------
; Read game map at pacmans's position PM_NT_LO/HI
;
get_pm_allowed:
			CLC
			LDA #<PACMAN_MAP
			ADC PM_NT_LO
			STA TMP2
			LDA #>PACMAN_MAP
			ADC PM_NT_HI
			STA TMP2+1
			LDY #0
			LDA (TMP2),Y
			STA PM_ALLOWED
			RTS

;---------------------------------------
; read from name table (i.e. screen)
;
pm_read_nametable:
			LDY PM_NT_LO			 ;; Set VRAM address to name table (VDP_REG2 * 0x400) + PM_NT_LO/HI
			LDA VDP_REGS+2
			ASL
			ASL
			CLC
			ADC PM_NT_HI
			JSR vdp_set_addr_r
			LDA VDP_RD_VRAM
			RTS
;---------------------------------------
; write to name table (i.e screen) at pacman's position
;  - will generally be to blank out a pill
;
pm_write_nametable:
			LDY PM_NT_LO			 ;; Set VRAM address to name table (VDP_REG2 * 0x400) + PM_NT_LO/HI
			LDA VDP_REGS+2
			ASL
			ASL
			CLC
			ADC PM_NT_HI
			JSR vdp_set_addr_w
			LDA #0
			STA VDP_WR_VRAM
			RTS

;---------------------------------------
; Get input from ACIA
;
pm_get_input_serial:
			LDA ACIA_STATUS
			AND #ACIA_STATUS_RX_FULL
			BEQ gis_no_dir_input
			LDA ACIA_DATA

			CMP #'q'
			BNE gis_check_space
			LDA #$FF
			STA pm_game
			RTS
gis_check_space:
			CMP #' '
			BNE gis_check_wasd
			LDA #$01
			STA pm_game
			RTS
gis_check_wasd:
			CMP #'a'
			BNE @check_d
			LDA #PM_DIR_L
			STA pm_input_dir
			RTS
@check_d:   CMP #'d'
			BNE @check_w
			LDA #PM_DIR_R
			STA pm_input_dir
			RTS
@check_w:   CMP #'w'
			BNE @check_s
			LDA #PM_DIR_U
			STA pm_input_dir
			RTS
@check_s:   CMP #'s'
			BNE gis_no_dir_input
			LDA #PM_DIR_D
			STA pm_input_dir
			RTS
gis_no_dir_input:
			;LDA #$FF
			;STA pm_input_dir
			RTS

;---------------------------------------
; Get input PC Keyboard
;
.if .def(PS2K) || .def(VKEYB)
pm_get_input_ps2k:
			jsr KBSCAN_GAME
			bcc gip_done
			ldx #0				  ; 0 in X means this is a make code
			lda KBD_CHAR
			cmp #SC_SPECIAL		 ; check for a break code
			bne gip_skip_set_breakcode

			; dont care about release
			rts
			;lda KBD_SPECIAL		 ; get break code
			;beq gip_done
			;ldx #1				  ; 1 in X means this is a break code
		
gip_skip_set_breakcode:
			cmp #SC_A
			beq gip_do_LEFT
			cmp #SC_RAW_LEFT_ARROW
			beq gip_do_LEFT
			;cmp #SC_NC_LEFT_ARROW
			;beq gip_do_LEFT

			cmp #SC_D
			beq gip_do_RIGHT
			cmp #SC_RAW_RIGHT_ARROW
			beq gip_do_RIGHT
			;cmp #SC_NC_RIGHT_ARROW
			;beq gip_do_RIGHT

			cmp #SC_W
			beq gip_do_UP
			cmp #SC_RAW_UP_ARROW
			beq gip_do_UP
			;cmp #SC_NC_UP_ARROW
			;beq gip_do_UP

			cmp #SC_S
			beq gip_do_DOWN
			cmp #SC_RAW_DOWN_ARROW
			beq gip_do_DOWN
			;cmp #SC_NC_DOWN_ARROW
			;beq gip_do_DOWN

			cmp #SC_SPC
			beq gip_do_START
			cmp #SC_Q
			beq gip_do_QUIT

gip_done:
			rts

gip_do_QUIT:
			lda #$FF
			sta pm_game
			rts
gip_do_START:
			lda #$01
			sta pm_game
			rts
gip_do_LEFT:
			lda #PM_DIR_L
			sta pm_input_dir
			rts
gip_do_RIGHT:
			lda #PM_DIR_R
			sta pm_input_dir
			rts
gip_do_UP:
			lda #PM_DIR_U
			sta pm_input_dir
			rts
gip_do_DOWN:
			lda #PM_DIR_D
			sta pm_input_dir
			rts
.endif

;---------------------------------------
; Process input
; Inputs:
;   - pm_input_dir - direction number (0=L,1=R,2=U,3=D)
;   - PM_DIR       - current movement direction (number)
;   - PM_ALLOWED   - allowed input dirs
; Outputs
;   - PM_DIR       - updated with new move direction
pm_process_input:
			LDA pm_input_dir
			BMI pi_done		 ; $FF = no input
			; if current dir is same as direction it is moving in, ignore
			CMP PM_DIR
			BEQ pi_done

			; switch to either processing up/down or left/right
			LDA PM_DIR		  ; check current direction
			CMP #PM_DIR_D
			BCS pi_curr_is_UD   ; 2 or 3 D/U

pi_curr_is_LR:			
			LDA pm_input_dir
			CMP #PM_DIR_L
			BEQ pi_dir_left
			CMP #PM_DIR_R
			BEQ pi_dir_right

			LDA PM_ST_SPR1_X
			AND #$07			; if X%8==0
			BEQ pi_check_ud	 ;   then fully in square so can check U/D as well
			;CMP #$01			; if X%8==1
			;BNE pi_done		 ;   then almost in square so
			;LDA PM_ST_SPR1_X	;   push to align
			;AND #$F8			;   by setting position in square to 0
			;STA PM_ST_SPR1_X
			BRA pi_done

pi_check_ud:
			LDA pm_input_dir
			CMP #PM_DIR_U
			BEQ pi_dir_up
			CMP #PM_DIR_D
			BEQ pi_dir_down
pi_done:
			;LDA #$FF			; clear input once it has been processed
			;STA pm_input_dir
			RTS

pi_curr_is_UD:			
			LDA pm_input_dir
			CMP #PM_DIR_U
			BEQ pi_dir_up
			CMP #PM_DIR_D
			BEQ pi_dir_down

			LDA PM_ST_SPR1_Y
			AND #$07			; if Y%8==0
			BEQ pi_check_lr		;   then fully in square so can check L/R as well
			;CMP #$01			; if Y%8==1
			;BNE pi_done		 ;   then almost in square so
			;LDA PM_ST_SPR1_Y	;   push to align
			;AND #$F8
			;STA PM_ST_SPR1_Y
			BRA pi_done

pi_check_lr:
			LDA pm_input_dir
			CMP #PM_DIR_L
			BEQ pi_dir_left
			CMP #PM_DIR_R
			BEQ pi_dir_right
			RTS

pi_dir_right:
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_R_BIT
			BEQ @skip
			LDA #PM_DIR_R
			STA PM_DIR
@skip:	  RTS
pi_dir_left:
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_L_BIT
			BEQ @skip
			LDA #PM_DIR_L
			STA PM_DIR
@skip:		RTS
pi_dir_up:
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_U_BIT
			BEQ @skip
			LDA #PM_DIR_U
			STA PM_DIR
@skip:		RTS
pi_dir_down:
			LDA PM_ALLOWED
			AND #PM_MAP_DIR_D_BIT
			BEQ @skip
			LDA #PM_DIR_D
			STA PM_DIR
@skip:		RTS

;------------------------------------------------------------------
; Quit
pm_quit_game:
			ld16 R0,quit_message
			JSR acia_puts
; restore interrupt vector 
			LDA IRQ_OLD
			STA IRQ_ADDR
			LDA IRQ_OLD+1
			STA IRQ_ADDR+1
; disable interrupts at CPU
			SEI

; disable interrupts from VDP
			LDA VDP_REGS+1		;; data to write is existing Reg1
			AND #$DF			;; unset interrupt bit
			STA VDP_REGS+1
			LDY #$81			;; register to write (1)
			JSR vdp_regwrite

			JSR vdp_getstatus   ;; clear interrupt flag in VDP

			RTS

;------------------------------------------------------------------
; VDP IRQ Handler
PM_IRQ:		PHP						; save status flags (so BCD is correct)
			PHA
			JSR pm_draw_sprites		; Write current sprite info to Sprite Atrr table
			DEC PM_IRQCOUNT			;; count--
			DEC PM_INTERRUPT		;; make interrupt flag != 0
			INC GHOST_IRQCOUNT

@skip:		JSR vdp_getstatus		;; read VDP status to reenable the VDP interrupt
			PLA 
			PLP
			RTI

;------------------------------------------------------------------
; draw sprites from table
;   -- draws all enabled sprites if update-flag is set
;   -- by writing to the Sprite Attribute table
;
pm_draw_sprites:
			LDA UPDATE_FLAG	
			BNE pm_do_draw
			RTS
pm_do_draw:
			phx
			phy
			LDA PM_NUMPRITES			
			BEQ pds_done
			ASL						; 4 bytes per sprite
			ASL
			TAX						; X has size of table

			LDY VDP_SAB				; set vdp up to write to Sprite Attrib Base
			LDA VDP_SAB+1
			JSR vdp_set_addr_w
			LDY #0					; index into table
pds_loop1:
			LDA PM_ST_SPR1_Y,Y		; read byte from table
			JSR vdp_write			; wrie to VDP
			INY
			DEX
			BNE pds_loop1
pds_done:
			STZ UPDATE_FLAG	
			ply
			plx
			RTS
			

;------------------------------------------------------------------
; Draw score to screen
pm_draw_score:
			; put score into R1,R+1
			LDA PM_SCORE
			STA R1
			LDA PM_SCORE+1
			STA R1+1
			; convert to decimal
			JSR BINBCD16
			ld16 R0,PM_STR_BUFFER
			JSR BCD4BYTE2STR
			
			LDA #27					; X
			LDY #9					; Y
			JSR vdp_set_pos
			JSR vdp_write_text  
			RTS
			
;------------------------------------------------------------------
; update the PM sprite animation
;   -- PM_IRQCOUNT starts at 0, decremented every 1/50 sec (20ms)
;   -- every 8*20=160ms the sprite pattern is changed 
pm_update_pm_sprite:
			LDA PM_IRQCOUNT
			AND #%00011000			; change sprite from 0-3 every 8th tick
			LSR
			LSR
			LSR						; value is now 0-3
			; add 4*PM_DIR
			STA TMP0
			LDA PM_DIR				; direction 
			ASL
			ASL
			CLC
			ADC TMP0				; add 4*PM_DIR to tick number
			; lookup sprite number
			TAY
			LDA PM_SPR_INDEX,Y
			; store in pattern
			STA PM_ST_SPR1_P
			RTS

;------------------------------------------------------------------
; update ghost animation - not dependent on pos of PM for now!
;   -- ghost sprite toggles between 9 and 10
;   -- GHOST_IRQCOUNT is incremented every 1/50 sec (20ms)
pm_update_ghost_sprite:
			LDA GHOST_IRQCOUNT
			AND #%00010000			; every 16*20ms = 320ms
			LSR
			LSR
			LSR
			LSR						; now 0-1
			CLC
			ADC #9					; now 9-10
pugs_save:
			STA PM_ST_SPR2_P
			STA PM_ST_SPR3_P
			STA PM_ST_SPR4_P
pugs_done:			
			RTS

;------------------------------------------------------------------
; Input - PM_ST_SPR1_X/Y
; Output - PM_POS_X/Y
;
calc_pm_pos:
			LDA PM_ST_SPR1_X
			CLC
			ADC #4
			LSR
			LSR
			LSR
			STA PM_POS_X
			LDA PM_ST_SPR1_Y
			CLC
			ADC #4
			LSR
			LSR
			LSR
			STA PM_POS_Y
			RTS

;------------------------------------------------------------------
; Read game map at Ghost n's position Gn_NT_LO/HI
; Input A = ghost number. 0==G1
get_ghost_allowed:
			ASL			; Ghost Number 
			ASL
			ASL 		; * 8
			TAX
		; check special
			LDA G1_NT_HI,X
			CMP #1
			BNE gga_readmap
			LDA G1_NT_LO,X
			CMP #$4E
			BNE gga_readmap
			CMP #$4F
			BNE gga_readmap
			LDA #$B
			STA G1_ALLOWED,X
			RTS

	gga_readmap:
            CLC
			LDA #<PACMAN_MAP
			ADC G1_NT_LO,X
			STA TMP2
			LDA #>PACMAN_MAP
			ADC G1_NT_HI,X
			STA TMP2+1
			LDY #0
			LDA (TMP2),Y
			STA G1_ALLOWED,X
			RTS

;------------------------------------------------------------------
;
move_ghosts:
			RTS

quit_message:
	.byte "Goodbye!",$0d,$0a,$00

.include "pm_char_set.inc65"
.include "pm_char_map.inc65"
.include "pm_sprites.inc65"
.include "pm_map.inc65"
