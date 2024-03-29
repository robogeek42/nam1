; vim: ts=4
		.setcpu "65C02"
		.include "zeropage.inc65"
		.include "macros.inc65"
		.include "video_common.inc65"
		.include "video_registers.inc65"
		.export spr_set_small
		.export spr_set_large
		.export spr_set_mag_on
		.export spr_set_mag_off
		.export vdp_init_sprites
		.export vdp_enable_sprites
		.export vdp_set_sprite_pos
		.export vdp_set_sprite_col
		.export vdp_set_sprite_early
		.export vdp_set_sprite_pattern
		.export vdp_load_sprite_data_from_mem

;.bss

; sprite movement table (not animated)
; struct {
;		   byte pattern;
;		   byte xpos;
;		   byte ypos;
;		   byte xspeed; 
;		   byte yspeed;
;		}
;spr_tab:	.res 4*32, 0

.code

;================================================================
;; Sprite routines

spr_set_small: ;; set small sprites in registers
				phay
				LDA VDP_REGS+1
				AND #$FD
				STA VDP_REGS+1
				LDY #$81			;; register 1
				JSR vdp_regwrite
				play
				RTS
				
spr_set_large: ;; set large sprites in registers
				phay
				LDA VDP_REGS+1
				ORA #$02
				STA VDP_REGS+1
				LDY #$81			;; register 1
				JSR vdp_regwrite
				play
				RTS				

spr_set_mag_on: 
				phay
				LDA VDP_REGS+1
				ORA #$01
				STA VDP_REGS+1
				LDY #$81			;; register 1
				JSR vdp_regwrite
				play
				RTS				

spr_set_mag_off:
				phay
				LDA VDP_REGS+1
				AND #$FE
				STA VDP_REGS+1
				LDY #$81			;; register 1
				JSR vdp_regwrite
				play
				RTS				


;----------------------------------------------------------------
; Initialise sprites - all off
; 	VPosY	= $D0
; 	VPosX	= $00
; 	Pattern  = $00
; 	EClk/Col = $00
;
vdp_init_sprites:
				phaxy
				LDY VDP_SAB
				LDA VDP_SAB+1
				JSR vdp_set_addr_w
				;; 32 sprites 4 bytes each = 128
				LDY #128
vis_loop:	   
				LDA #$D0	;; D0 in vertical pos turns off sprite processing
				JSR vdp_write
				DEY			 ;; 2 cycles = 2us at 1MHz
				LDA #0 		;; zero in other 3 fields
				JSR vdp_write
				DEY
				JSR vdp_write
				DEY
				JSR vdp_write
				DEY
				BNE vis_loop
				plaxy
				RTS

;----------------------------------------------------------------
; Enable first N sprites (N in Acc)
; only write posy - don't affect other numbers (i.e. posx/pattern/col)
; Max N is 32, 0 = Disable all
; SAB is on 128 byte boundary so sprite address can be added to 
; LSB of SAB table address without doing 16bit add
vdp_enable_sprites:
				phaxy
				LDX #0				; counter (all 32)
				LDY VDP_SAB		; SAB lo
ves_loop:		LDA VDP_SAB+1	; hi
				JSR vdp_set_addr_w
				CPX ZP_TMP0			; ZP_TMP0 has N
				BCC @enable			; Branch if X < N
				LDA #$D0
				JMP @dowrite
@enable:		LDA #0 
@dowrite:		
				JSR vdp_write
				INY					; move to next sprite
				INY
				INY
				INY
				INX					; counter++
				CPX #32
				BNE ves_loop
				plaxy
				RTS

;----------------------------------------------------------------
; Set position of Sprite S
; Sprite number in ZP_TMP0, Pos X in ZP_TMP0+1, Pos Y in ZP_TMP2
vdp_set_sprite_pos:
				phay
				CLC
				LDA ZP_TMP0			; S*4
				ASL
				ASL
				ADC VDP_SAB		; add LSB of base
				TAY
				LDA VDP_SAB+1
				JSR vdp_set_addr_w
				NOP
				LDA ZP_TMP2			; Y first
				JSR vdp_write
				LDA ZP_TMP0+1		; then X
				JSR vdp_write
				play
				RTS

;----------------------------------------------------------------
; Set color of Sprite S
; Sprite number in ZP_TMP0, Color in ZP_TMP0+1
vdp_set_sprite_col:
				phay
				CLC
				LDA ZP_TMP0			; S*4
				ASL
				ASL
				ADC VDP_SAB		; add LSB of base
				ADC #3				; 4th member
				TAY
				LDA VDP_SAB+1
				JSR vdp_set_addr_r	; read current value of colour/earlyclock
				JSR vdp_read
				AND #$F0			; preserve the clock bit
				ORA ZP_TMP0+1		; and write new color
				STA ZP_TMP0+1		; save
				LDA VDP_SAB+1
				JSR vdp_set_addr_w	; set address again - write this time
				LDA ZP_TMP0+1		; write modified color to VRAM
				JSR vdp_write
				play
				RTS

;----------------------------------------------------------------
; Set Early Clock bit of Sprite S
; Sprite number in ZP_TMP0, Clock bit in ZP_TMP0+1 (either $80=on or $00=off)
vdp_set_sprite_early:
				phay
				CLC
				LDA ZP_TMP0			; S*4
				ASL
				ASL
				ADC VDP_SAB		; add LSB of base
				ADC #3				; 4th member
				TAY
				LDA VDP_SAB+1
				JSR vdp_set_addr_r	; read current value of colour/earlyclock
				JSR vdp_read
				AND #$0F			; preserve the colour nibble
				ORA ZP_TMP0+1
				STA ZP_TMP0+1		; save
				LDA VDP_SAB+1
				JSR vdp_set_addr_w	; set address again - write this time
				LDA ZP_TMP0+1		; write modified color to VRAM
				JSR vdp_write
				play
				RTS


;----------------------------------------------------------------
; Set pattern of Sprite S
; Sprite number in ZP_TMP0, Pattern name P in ZP_TMP0+1
vdp_set_sprite_pattern:
				phay
				CLC
				LDA ZP_TMP0			; S*4
				ASL
				ASL
				ADC VDP_SAB		; add LSB of base
				ADC #2				; 3rd member
				TAY
				LDA VDP_SAB+1
				JSR vdp_set_addr_w	; set write address
				LDA ZP_TMP0+1
				JSR vdp_write
				play
				RTS

;----------------------------------------------------------------
; Set data of sprite pattern P from address in ZP
; Sprite Pattern number in ZP_TMP2, address in ZP_TMP0/1 (low/hi)
vdp_load_sprite_data_from_mem:
				phay
				LDY ZP_TMP2			;; use P as counter

				LDA VDP_REGS+6   ;; Reg 6 has Pattern table addr
				ASL					;; 2k boundaries (*0x800)
				ASL					;; mult by 8 to give MSB
				ASL
				STA TMP2+1			;; put patt table addr in TMP2/TMP2+1
				STZ TMP2			;;

				CPY #0				;; if P=0 don't need to add to addr
				BEQ vssp_setvram

@vssp_loop1:	add8To16 #8, TMP2	;; add 8 P times
				DEY
				BNE @vssp_loop1

vssp_setvram:	LDY TMP2			;; set vram write address
				LDA TMP2+1
				JSR vdp_set_addr_w

				LDY #0				;; copy data into vram
@vssp_loop:		LDA (ZP_TMP0),Y
				JSR vdp_write
				INY
				CPY #8
				BNE @vssp_loop
				play
				RTS

