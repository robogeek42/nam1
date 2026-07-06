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

CHAN = svars+8

sndvars = $7010
snd_attn:
SND0ATTN        = sndvars+0
SND1ATTN        = sndvars+1
SND2ATTN        = sndvars+2
SND3ATTN        = sndvars+3
snd_freql:
SND0FREQL       = sndvars+4
SND1FREQL       = sndvars+5
SND2FREQL       = sndvars+6
SND3FREQL       = sndvars+7
snd_freqh:
SND0FREQH       = sndvars+8
SND1FREQH       = sndvars+9
SND2FREQH       = sndvars+10
SND3FREQH       = sndvars+11

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
        LDA #$0F
        STA SND0ATTN
        STA SND1ATTN
        STA SND2ATTN
        STA SND3ATTN
		JSR snd_all_off

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
        BEQ do_tick

        LDA IRQ_COUNT
        CMP #20
        BCS do_sound_atten
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
		JSR snd_all_off
		RTS

;---------------------------------------
do_tick:
        LDA #GS_RUNNING
        STA game_state
        LDA #'.'
        JSR vdp_write_char
        JMP main_loop

do_sound_atten:
        LDX #0
    @chan_loop:
        STX CHAN
        JSR sound_attenuate       ; gradually attenuate any playing sound on channel
        INX
        CPX #4
        BNE @chan_loop
        STZ IRQ_COUNT
        JMP main_loop

;-----------------------------------------------------
; Keyboard scan - approx 105ms
get_input_ps2k:
		JSR KBSCAN_GAME
		BCC gip_done

		LDA KBD_CHAR
		CMP #SC_SPECIAL	 ; check for a break code
		BEQ gip_done		; ignore

		LDA KBD_CHAR
		CMP #SC_ESCAPE
		beq gi_do_QUIT

        JSR check_keys

gip_done:
		rts

gi_do_QUIT:
		LDA #GS_QUIT
		STA game_state
		rts

check_keys:
        LDX #0
    ck_key_loop:
        CMP mn_keys,X
        BEQ ck_play
        INX
        INX
    ck_loop_over:
        CPX #NKEYS*2
        BNE ck_key_loop
        RTS

    ck_play:
        INX
        PHA             ; PHA_PLA_1
        LDA mn_keys,X   ; get offset into notes table
        TAY
LDA mnotes,Y
jsr acia_putc
        INY             ; skip 1st char
LDA mnotes,Y
jsr acia_putc
        INY             ; skip 2nd char
LDA mnotes,Y
jsr acia_putc
lda #' '
jsr acia_putc
        INY             ; skip 3rd char

        LDA mnotes,Y    ; load 1st part of freq byte
        STA ZP_TMP0     ; and save
ld16 R0, strbuff
jsr fmt_hex_string
jsr acia_puts
lda #','
jsr acia_putc
        INY             ;
        LDA mnotes,Y    ; load 2nd part 
        STA ZP_TMP0+1   ; and save
ld16 R0, strbuff
jsr fmt_hex_string
jsr acia_puts
jsr acia_put_newline

        ; find channel to play on
        ; check if any channel doesn't have anything playing

        PHX             ; PHX_PLX_1
        LDX #0
    @find_chan_loop:
        LDA snd_attn,X      ; current atten on Chan X
pha
lda #'a'
jsr acia_putc
ld16 R0, strbuff
pla
jsr fmt_hex_string
jsr acia_puts
jsr acia_put_newline
        CMP #$0E            ; FIXME I don't know why this has to be 0E instead of 0F
                            ; if I set 0F it always skips chan 2 
        BCS @play_on_chan   ; if off play on chan X
        INX                 ; check next chan
        CPX #3              ; can't play on 3=noise
        BNE @find_chan_loop
        LDX #0
    @play_on_chan:
        STX CHAN            ; X will be 0 if we couldn't find anything
        JSR play_vals
        PLX             ; PHX_PLX_1
        PLA             ; PHA_PLA_1
        INX             ; move on to next byte in mn_leys table - i.e. next key to check
        JMP ck_loop_over

;----------------------------------------------------------------------
; Sound functions
;
; set reducing attenuation level for channel CHAN
sound_attenuate: 
        PHA
        PHX
        LDX CHAN
        LDA snd_attn,X      ; current sound volume (attenuation) on chan X
		CMP #$0F
        BCS @over           ; full attn 
        INC snd_attn,X      ; increase attn on chan X
        ; build byte to send to SN76489
        LDA snd_reg_att,X   ; get base byte value for attenuating reg X
        ORA snd_attn,X      ; put in attn level
        ; send it
;pha
;lda #'v'
;jsr acia_putc
;ld16 R0, strbuff
;pla
;jsr fmt_bin_string
;jsr acia_puts
;jsr acia_put_newline
		JSR snd_write
@over:
        PLX
        PLA
		RTS

; set frequency on channel CHAN
; Set chan ccc 10-bit frequency DDDDDDAAAA as 2 bytes [#1cccAAAA,#00DDDDDD]
; ZP_TMP0,ZP_TMP0+1 have the two parts of freq
play_vals:
        PHA
        PHX
        LDX CHAN
lda #'c'
jsr acia_putc
ld16 R0, strbuff
TXA
jsr fmt_hex_string
jsr acia_puts
lda #' '
jsr acia_putc
        LDA snd_reg_freq,X  ; Freq Channel CHAN - get base byte
        ORA ZP_TMP0+1       ; data = AAAA
ld16 R0, strbuff
jsr fmt_bin_string
jsr acia_puts
pha
lda #' '
jsr acia_putc
pla
		JSR snd_write
        CPX #3
        BEQ @skip_second_byte ; chan 3 is noise, it doesn't have an extra byte
        LDA ZP_TMP0         ; Freq DDDDDD into second byte
ld16 R0, strbuff
jsr fmt_bin_string
jsr acia_puts
jsr acia_put_newline
		JSR snd_write
    @skip_second_byte:
        LDA snd_reg_att,X   ; chan n vol = full (0)
		JSR snd_write
        STZ snd_attn,X
        PLX
        PLA
        RTS

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
        INC IRQ_COUNT			    ; another IRQ counter - for attenuator
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

snd_reg_freq:
    .byte %10000000, %10100000, %11000000, %11100000
snd_reg_att:
    .byte %10010000, %10110000, %11010000, %11110000

NKEYS=37
mn_keys:
    .byte SC_Q,12*5
    .byte SC_2,13*5
    .byte SC_W,14*5
    .byte SC_3,15*5
    .byte SC_E,16*5
    .byte SC_R,17*5
    .byte SC_5,18*5
    .byte SC_T,19*5
    .byte SC_6,20*5
    .byte SC_Y,21*5
    .byte SC_7,22*5
    .byte SC_U,23*5
    .byte SC_I,24*5
    .byte SC_9,25*5
    .byte SC_O,26*5
    .byte SC_0,27*5
    .byte SC_P,28*5
    .byte SC_LFTSQBRKT,29*5
    .byte SC_EQUALS,30*5
    .byte SC_RGTSQBRKT,31*5

    .byte SC_Z,0*5
    .byte SC_S,1*5
    .byte SC_X,2*5
    .byte SC_D,3*5
    .byte SC_C,4*5
    .byte SC_V,5*5
    .byte SC_G,6*5
    .byte SC_B,7*5
    .byte SC_H,8*5
    .byte SC_N,9*5
    .byte SC_J,10*5
    .byte SC_M,11*5
    .byte SC_COMMA,12*5
    .byte SC_L,13*5
    .byte SC_DOT,14*5
    .byte SC_SEMICOLON,15*5
    .byte SC_FWDSLASH,16*5

.include "../mnotes.inc65"
