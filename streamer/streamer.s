; vim: ts=4 sw=4
; Audio streaming test

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

; additonal vars in basic program area
svars = $7000

IRQ_OLD         = svars+0	   ; 2 bytes
IRQ_COUNT       = svars+2	   ; 2 bytes
game_state      = svars+4	   ; 1 byte
                               ; 1 byte blank
TIMER1_COUNT    = svars+6      ; 2 bytes

; IRQ location - points to address part of JMP xxxx
IRQ_ADDR = $20A

GS_RUNNING  = 0
GS_QUIT     = 1
GS_IRQ      = 2

.bss
    BUFFER_LENGTH = 32
strbuff:
    .res BUFFER_LENGTH + 1, 0

.code

streamer:
;=======================================
; Initialise

; sound channels all off
.ifdef SOUND
		JSR snd_all_off
.endif

; init keyboard
.if .def(PS2K) || .def(VKEYB)
		jsr KBINIT
.endif

;---------------------------------------
; game state vars
		LDA #GS_RUNNING
		STA game_state

;---------------------------------------
; set mode and print welcome
		LDA #0
		JSR vdp_set_mode
		ld16 R0,msg_hello
		JSR vdp_write_text


;---------------------------------------
; Setup interrupt handler
pih_save_old:
		LDA IRQ_ADDR
		STA IRQ_OLD
		LDA IRQ_ADDR+1
		STA IRQ_OLD+1
		
pih_setup_new:
		LDA #<NEW_IRQ
		STA IRQ_ADDR
		LDA #>NEW_IRQ
		STA IRQ_ADDR+1

; Enable IRQ

		; setup of 6522#1 Timer1
        JSR st_setup_timer


; Start allowing interrupts at CPU
		CLI

;=======================================
; Main loop
main_loop:
.if .def(PS2K) || .def(VKEYB)
		JSR get_input_ps2k
.endif

		LDA game_state
		CMP #GS_QUIT
		BEQ quit_main
        CMP #GS_IRQ
        BEQ do_thing

		JMP main_loop

;---------------------------------------
quit_main:
		ld16 R0,msg_goodbye
		JSR vdp_write_text
		; restore interrupt vector 
		LDA IRQ_OLD
		STA IRQ_ADDR
		LDA IRQ_OLD+1
		STA IRQ_ADDR+1
		; disable interrupts at CPU
		SEI

		; disable interrupts from 6522
        lda #%00000000
        sta VIA1+VIA_ACR                ; Places Timer1 into one-shot mode

		; stop any sounds
.ifdef SOUND
		JSR snd_all_off
.endif
		RTS

;---------------------------------------
do_thing:
        LDA #GS_RUNNING
        STA game_state
        LDA #'.'
        JSR vdp_write_char
        JMP main_loop

;-----------------------------------------------------
; Keyboard scan - approx 105ms
get_input_ps2k:
		JSR KBSCAN_GAME
		BCC gip_done

		LDA KBD_CHAR
		CMP #SC_SPECIAL	 ; check for a break code
		BEQ gip_done		; ignore

ld16 R0, strbuff
JSR fmt_hex_string
JSR vdp_write_text
LDA #' '
JSR vdp_write_char

		LDA KBD_CHAR
		CMP #SC_Q
		beq gi_do_QUIT
		CMP #'Q'
		beq gi_do_QUIT
		CMP #'q'
		beq gi_do_QUIT

gip_done:
		rts

gi_do_QUIT:
		LDA #GS_QUIT
		STA game_state
		rts

;-----------------------------------------------------
; Timer setup
st_setup_timer:
        ; Set up Timer1 on 65C22 VIA in free run mode to generate an interrupt every 10ms (0.01s).
        lda #$62                        ; Sets the counter to track number of interrupts (100)
        sta TIMER1_COUNT + 1            ; Hold this as a constant to reset to. Like a latch.
        sta TIMER1_COUNT                ; This will decrement then be reset with the above value.
        lda #%01000000
        sta VIA1+VIA_ACR                ; Places Timer1 into continuous interrupts (free run mode).
        ; write counters
        lda #$FE                        ; 0.01s @ 2.4576 Mhz (-2 cycles) = 24,574 ($5FFE).
        sta VIA1+VIA_T1C_L
        lda #$5F
        sta VIA1+VIA_T1C_H
        ; write latches
        lda #$FE                        ; 0.01s @ 2.4576 Mhz (-2 cycles) = 24,574 ($5FFE).
        sta VIA1+VIA_T1L_L
        lda #$5F
        sta VIA1+VIA_T1L_H

        lda #%11000000                  ; Sets interrupts for Timer1.
        sta VIA1+VIA_IER
        RTS
;-----------------------------------------------------

; Interrupt handler
NEW_IRQ:
        phaxy
        LDA VIA1+VIA_T1C_L          ; clear interupt flag
		;INC IRQ_COUNT			   ;; count++
        DEC TIMER1_COUNT
        BNE ni_exit
        
        ; reset timer count
        LDA TIMER1_COUNT+1
        STA TIMER1_COUNT
        
        LDA #GS_IRQ
        STA game_state

    ni_exit:
        plaxy
		RTI
;-----------------------------------------------------

msg_goodbye:
	.byte $0D,$0A,"Goodbye",$0D,$0A,$00
msg_hello:
	.byte $0D,$0A,"Welcome to Audio Streamer Test",$0D,$0A,$00
msg_anykey:
	.byte $0D,$0A,"Press any key",$0D,$0A,$00
msg_pressq:
	.byte $0D,$0A,"Press Q to quit",$0D,$0A,$00
;msg_newline:		   ; defined in basic.s
;	.byte $0D,$0A,$00

