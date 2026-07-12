; vim: ts=4 et sw=4
; SN76489 Sound Chip
;
        .setcpu "65C02"
        .include "zeropage.inc65"
        .include "acia.inc65"
        .include "string.inc65"
        .include "macros.inc65"
        .include "io.inc65"
        .include "sound_vars.inc65"

.export snd_all_off
.export snd_hello
.export snd_write
.export snd_play_vgmdata
.export snd_beep
.export snd_attenuate
.export snd_play_vals
.export snd_setup_timer
.export snd_stop_timer

.bss
strbuf: .res 8, 0
snd_vars: .res 8, 0

.export snd_vars
.code

;--------------------------------------------------------------
; Support routines for sound chip interfaced through VIA
snd_write:
        PHX
        PHA
		; Set control signals to off
		LDA SND_VIA_CTL
		ORA #SND_VIA_WE_CE
        STA SND_VIA_CTL
		; Latch output data
        PLA
        STA SND_VIA_DATA
.ifdef DEBUG_PRINT_SOUND
        ; print Binary of SND data to serial
        ld16 R0, snd_data_msg
        JSR acia_puts
        ld16 R0,strbuf
        ;JSR fmt_bin_string
        JSR fmt_hex_string
        JSR acia_puts
        JSR acia_put_newline
.endif
		; Set write enable/chip enable
		LDA SND_VIA_CTL
        AND #SND_VIA_NOT_WE_CE
        STA SND_VIA_CTL
		; wait for at least 32 cycles of sound clock
        ; Delay used to ensure data is latched for 32 cycles of sound clock
        ; @ 4MHz this is 8us, @3.64MHz this is 9us
        ; At system clock of 2.45MHz 9us is 22 cycles
        LDX #3
        JSR snd_delay
		; Set control signals to off
		LDA SND_VIA_CTL
		ORA #SND_VIA_WE_CE
        STA SND_VIA_CTL
        PLX
		RTS

;--------------------------------------------------------------
; Generic routines
;--------------------------------------------------------------

;--------------------------------------------------------------
; Delay : delay length (X*6 + 12 including JSR and RTS)
;   	to get 24 cycles need X=2
;       : delay length (X*4+12).
;         x=1:16 x=2:20 x=3:24 x=4:30 x=256:1036
snd_delay:
@loop:  NOP 		; 2 cycles
        NOP
        NOP
        NOP
        NOP
		DEX			; 2 cycles
		BNE @loop	; 2 cycles (probably)
		RTS			; 6 cycles

snd_wait:
@loop2: LDX #0
        JSR snd_delay
        DEY
        BNE @loop2
        RTS

snd_all_off:
        phx
        pha
        LDA #%10011111
        JSR snd_write
        LDA #%10111111
        JSR snd_write
        LDA #%11011111
        JSR snd_write
        LDA #%11111111
        JSR snd_write
        pla
        plx
        RTS
; Tone register DDDDDDdddd (10bit)
; to get X Hz, set DDDDDDdddd to 115200/X
; e.g. 440Hz : 115200/440 = 262 = $106 = %0100000110)
;                                         DDDDDDdddd
; 1st byte 
;   %1cctdddd
;     |||````-- Data
;     ||`------ Type (0=tone 1=volume)
;     ``------- Channel (0-3)
;
; 2nd byte
;  %0-DDDDDD
;    |``````-- Data
;    `-------- Unused
;
; 
        
snd_hello:
        phx
        phy
        pha
        ; Set frequency to %1000001000 = 528 -> 3.6864MHz/32*528 = 218Hz
        LDA #%10001000  ; Freq dddd Channel 0
        JSR snd_write
        LDA #%00100000  ; Freq DDDDDD 
        JSR snd_write
        LDA #%10010111  ; Attn Channel 0 : 0 = no atten (full vol). This is 7:half vol
        JSR snd_write

        LDY #$FF
        JSR snd_wait

        ; Set frequency to %0001111111 = 127 -> 3.6864MHz/32*127 = 907Hz
        LDA #%10001111  ; Freq Channel 0
        JSR snd_write
        LDA #%00000111  ; Freq DDDDDD 
        JSR snd_write

        LDY #$AF
        JSR snd_wait

        pla
        ply
        plx
        RTS

        ; 3.6864 /32 = 115200
        ; to get X Hz, set freq to 115200/X
snd_beep:
        phx
        phy
        pha
        ; play a note at 440Hz (262=$106=%0100000110)
        LDA #%10000110  ; Freq dddd Channel 0
        JSR snd_write
        LDA #%00010000  ; Freq DDDDDD 
        JSR snd_write
        LDA #%10010111  ; Attn Channel 0 : 0 = no atten (full vol). This is 7:half vol
        JSR snd_write

        LDY #$2F
        JSR snd_wait
        LDA #%10011111  ; Attn Channel 0 : 0 = no atten (full vol). This is 15:off
        JSR snd_write
        
        pla
        ply
        plx
        RTS
;----------------------------------------------------------------
; Waits for 52 cycles - approx 1 sample (55)
wait_1_samples:
;lda #'w'
;jsr acia_putc
;rtS

        PHY         ; 4
		LDY #3		; 2 cycles
@loop:  NOP 		; 2 cycles \
		NOP			; 2 cycles |
		NOP			; 2 cycles | 10 cycles
		DEY			; 2 cycles |
		BNE @loop	; 2 cycles /
        PLY         ; 4
		RTS			; 6 cycles

;----------------------------------------------------------------
; waits for 14190+12+10 = 14212 cycles whichis approx 256 samples
wait_256_samples:
;lda #'W'
;jsr acia_putc
;rts
        PHY         ; 4 cycles
		LDY #233	; 2 cycles	 - 253*56=14190 cycles
@loop:  
		JSR wait_1_samples ;   \
		DEY			; 2 cycles | 52+4=56 cycles
		BNE @loop	; 2 cycles /
        PLY         ; 4 cycles
		RTS			; 6 cycles

		
;----------------------------------------------------------------
; Play a VGM file (stripped of its header)
; Pass address in R2
; waits are in samples @ 44100Hz. 1 sample wait = 55.56 cycles
; (256 samples = 14222 cycles approx 5.8ms)
;
;------------------------
; do
;  get R2,R2+1 -> W
;  wait W cycles
;  get R2+2 -> C
;  if W==0 && C==0 break;
;  R2+=3
;  for Y=0 to C-1
;    send R2[Y] to VGM
;  next
; until 0
;------------------------

; Play a VGM file 
snd_play_vgmdata:
		phx
		phy
		pha
;------------------------
; do
;------------------------
spv_do_loop:
;------------------------
;  get R2,R2+1 -> W
;------------------------
		LDY #0
		LDA (R2),Y
		STA ZP_TMP0
		INY
		LDA (R2),Y
		STA ZP_TMP0+1

; DEBUG
;ld16 R0,strbuf
;lda #'W'
;jsr acia_putc
;lda ZP_TMP0+1
;jsr fmt_hex_string
;jsr acia_puts
;lda ZP_TMP0
;jsr fmt_hex_string
;jsr acia_puts

		; if W==0 skip wait
		LDA ZP_TMP0
		BNE spv_wait
		LDA ZP_TMP0+1
		BNE spv_wait
		JMP spv_get_count
;------------------------
;  wait W cycles
;------------------------
spv_wait:
		; first wait 256* HI(W) samples
		LDX ZP_TMP0+1
        BEQ @skiphi
	@loop_hi:
		JSR wait_256_samples
		DEX
		BNE @loop_hi
    @skiphi:
		; then wait LO(W) samples
		LDX ZP_TMP0
        BEQ spv_get_count
	@loop_lo:
		JSR wait_1_samples
		DEX
		BNE @loop_lo
;------------------------
;  get R2+2 -> C
;------------------------
spv_get_count:
		LDY #2
        LDA (R2),Y
		STA ZP_TMP2

; DEBUG
;lda #'C'
;jsr acia_putc
;lda ZP_TMP2
;jsr fmt_hex_string
;jsr acia_puts
;lda #' '
;jsr acia_putc
;jsr acia_put_newline

;------------------------
;  if W==0 && C==0 break;
;------------------------
		LDA ZP_TMP2
		BEQ spv_end
;------------------------
;  R2+=3
;------------------------
		add8To16 #3,R2
;------------------------
;  for X=0 to C-1
;------------------------
		LDY #0
spv_loop1:
;------------------------
;    send R2[X] to VGM
;------------------------
		LDA (R2),Y
; DEBUG
;jsr fmt_hex_string
;jsr acia_puts
;lda #','
;jsr acia_putc
;lda (R2),Y

		JSR snd_write
;------------------------
;  next
;------------------------
		INY
        CPY ZP_TMP2
		BNE spv_loop1
;DEBUG
;Jsr acia_put_newline

;------------------------
;  until 0
;------------------------
        add8To16 ZP_TMP2, R2
        JMP spv_do_loop
spv_end:
;DEBUG
;lda #'E'
;jsr acia_puts
;jsr acia_put_newline
		pla
		ply
		plx
		RTS
 
;----------------------------------------------------------------------
; Sound functions
;
; set reducing attenuation level for channel CHAN passed as X
snd_attenuate: 
        PHA
        LDA SND_ATTN0,X      ; current sound volume (attenuation) on chan X
		CMP #$0F
        BCS @over           ; full attn 
        INC SND_ATTN0,X      ; increase attn on chan X
        ; build byte to send to SN76489
        LDA snd_reg_att,X   ; get base byte value for attenuating reg X
        ORA SND_ATTN0,X      ; put in attn level
        ; send it
;pha
;lda #'v'
;jsr acia_putc
;ld16 R0, strbuf
;pla
;jsr fmt_bin_string
;jsr acia_puts
;jsr acia_put_newline
		JSR snd_write
        CLC
@over:
        PLA
		RTS

;------------------------------------------------------------------
; set frequency on channel CHAN passed as X reg
; Set chan ccc 10-bit frequency DDDDDDAAAA as 2 bytes [#1cccAAAA,#00DDDDDD]
; ZP_TMP0,ZP_TMP0+1 have the two parts of freq
snd_play_vals:
        PHA
lda #'c'
jsr acia_putc
ld16 R0, strbuf
TXA
jsr fmt_hex_string
jsr acia_puts
lda #' '
jsr acia_putc
        LDA snd_reg_freq,X  ; Freq Channel CHAN - get base byte
        ORA ZP_TMP0         ; data = AAAA
ld16 R0, strbuf
jsr fmt_bin_string
jsr acia_puts
pha
lda #' '
jsr acia_putc
pla
		JSR snd_write
        CPX #3
        BEQ @skip_second_byte ; chan 3 is noise, it doesn't have an extra byte
        LDA ZP_TMP0+1         ; Freq DDDDDD into second byte
ld16 R0, strbuf
jsr fmt_bin_string
jsr acia_puts
jsr acia_put_newline
		JSR snd_write
    @skip_second_byte:
        LDA snd_reg_att,X   ; chan n vol = full (0)
		JSR snd_write
        STZ SND_ATTN0,X

        PLA
        RTS

;-----------------------------------------------------
; Timer setup for attenuation
snd_setup_timer:
        pha
        lda VIA1+VIA_IER        ; Check if timer1 (bit 6) is enabled
        and #%01000000
        beq sst_enable          ; branch if timer1 not enabled
        pla
        rts

    sst_enable:
ld16 R0, msg_setuptimer
jsr acia_puts
        pla
        ; Set up Timer1 on 65C22 VIA in free run mode to generate an interrupt every 10ms (0.01s).
        ; and then a further counter to count a number of these interrupts before attenuating
        ;lda #$62                        ; Sets the counter to track number of interrupts (100)
        sta SND_TIMER1_CNT + 1           ; Hold this as a constant to reset to. Like a latch.
        sta SND_TIMER1_CNT               ; This will decrement then be reset with the above value.
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

        CLI                             ; Clear Interrupt Disable = allow interrupts

        RTS

snd_stop_timer:
ld16 R0, msg_stoptimer
jsr acia_puts
        SEI                             ; Set Interrupt Disable
        lda #%01000000                  ; disable interrupts for Timer1
        sta VIA1+VIA_IER
        RTS

msg_setuptimer:
    .byte "start timer",$0d,$0a,$00
msg_stoptimer:
    .byte "stop timer",$0d,$0a,$00
;-----------------------------------------------------

snd_reg_freq:
    .byte %10000000, %10100000, %11000000, %11100000
snd_reg_att:
    .byte %10010000, %10110000, %11010000, %11110000

snd_data_msg: .byte "SND:",$00

