.setcpu "65C02"

.export main

.include "macros.inc65"
.include "zeropage.inc65"
.include "acia.inc65"
.include "scancodes.inc65"
.include "io.inc65"
.include "string.inc65"
.include "print_util.inc65"
.include "video.inc65"
.include "video_common.inc65"
.include "video_registers.inc65"
.include "sprite.inc65"
.include "sd.inc65"
.include "kbdvia.inc65"
.include "decomp.inc65"
.include "sound.inc65"
.include "bcd.inc65"
.include "pckybd.inc65"
.ifdef UCHESS2
.include "uchess2.inc65"
.endif
.ifdef IMAGETEST
.include "video_load_mc.inc65"
.endif
.include "basic.s"

.ifdef PONG
.import pong
.endif
.ifdef PACMAN
.import pacman
.endif
.ifdef BREAKOUT
.import breakout
.endif

.segment "VECTORS"

                .word   NMI_vec
                .word   RES_vec
                .word   MY_IRQ_vec
;                .word   IRQ_vec

.bss
;-----------------------------------------------------
; buffer for monitor
;-----------------------------------------------------
                BUFFER_LENGTH = 60
buffer:         .res BUFFER_LENGTH+1, 0
basicvars:      .res 1,0
                PAGECNT = basicvars+0
.code

RES_vec:
main:           CLD           ; Clear decimal bit
                LDX #$ff    ; Reset stack
                TXS

                ; set up vectors and interrupt code, copy them to page 3
                LDY    #END_CODE-LAB_vec    ; set index/count
LAB_stlp:
                LDA    LAB_vec-1,Y        ; get byte from interrupt code
                STA    VEC_IN-1,Y        ; save to RAM
                DEY                    ; decrement index/count
                BNE    LAB_stlp        ; loop if more to do

                STZ OUT_LIST_SD

                ; initialise ACIA serial comms
                JSR acia_init

.ifdef KEYB
                ld16 R0,msg_init_keyboard
                JSR acia_puts
                JSR kbd_init
.endif
                ;ld16 R0,buffer
                ;JSR acia_put_newline
                ;LDX #<VDP_REGS
                ;LDA #>VDP_REGS
                ;JSR print_16bit_hex_string      ; print it
                ;JSR acia_put_newline

                ; Initialise VIA2 for SD card and Sound and KBD
                ; Port A output data for sound
                LDA #$FF
                STA VIA2 + VIA_DDRA
                LDA #(SD_CLK | SD_CS | SD_DI | SND_VIA_WE_CE )    ; Set output pins
                STA VIA2 + VIA_DDRB              ; SD card is attached to PortB of VIA2

.ifdef SOUND
                JSR snd_all_off
.endif ; SOUND

.if .def(PS2K) || .def(VKEYB)
                ld16 R0,msg_init_ps2k
                JSR acia_puts
                JSR KBINIT
.endif
                
                ; display welcome message in the Serial Console
                ld16 R0, msg_welcome
                JSR acia_puts

                ; Setup video with Mode 0
                LDA #0
                JSR vdp_set_mode
                
                ; display welcome message on video screen
                ld16 R0, msg_welcome
                JSR vdp_write_text

.ifdef SDIO
.ifdef KEYB
                ; Skip SD init if key is pressed
                JSR kbd_scan
                BCS skip_sdinit
.endif
                
                ; SD Card and filesystem
                JSR init_sdcard
                JSR init_fs
skip_sdinit:
.endif

.ifdef SOUND
                ; Play welcome sound
                JSR snd_hello
                JSR snd_all_off
.endif ; SOUND

                ; clear address used for 'm' memory dump command
                LDA #0
                STA RES
                STA RES+1

; Go straight to BASIC!
                LDA #<LAB_COLD
                STA TMP0
                LDA #>LAB_COLD
                STA TMP0+1
                JMP (TMP0)

; ---------------------------------------------------------
; -- Command loop
main_monitor:
                ; display prompt 
loop:           ld16 R0, prompt
                JSR acia_puts
                ; read input line into a buffer
                ld16 R0, buffer
                LDA #BUFFER_LENGTH
                JSR acia_gets
                LDA buffer

                ; m = print memory address
@cmd_m:         cmp #'m'
                bne @cmd_m_end
                jsr cmd_memory
                jmp loop
                @cmd_m_end:

                ; p = dump memory page
@cmd_p:         cmp #'p'
                bne @cmd_p_end
                jsr cmd_dump_page
                jmp loop
                @cmd_p_end:

                ; w = write data to adrress
@cmd_w:         cmp #'w'
                bne @cmd_w_end
                jsr cmd_write
                jmp loop
                @cmd_w_end:
                
                ; j = jump to address
@cmd_j:         cmp #'j'
                bne @cmd_j_end
                jsr cmd_jump
                jmp loop
                @cmd_j_end:

@cmd_b:         cmp #'b'
                bne @cmd_b_end
                jsr cmd_basic
                jmp loop
                @cmd_b_end:

.ifdef UCHESS2
@cmd_c:         cmp #'c'
                bne @cmd_c_end
                jsr cmd_uchess2
                jmp loop
                @cmd_c_end:
.endif

@cmd_vd:        cmp #'v'
                bne @cmd_vd_end
                lda buffer+1
                cmp #'d'
                bne @cmd_vd_end
                lda buffer+2
                cmp #' '
                bne @cmd_vd_end
                jsr cmd_vram_dump
                jmp loop
                @cmd_vd_end:

@cmd_sd:        cmp #'s'
                bne @cmd_sd_end
                lda buffer+1
                cmp #'d'
                bne @cmd_sd_end
                jsr cmd_dir
                jmp loop
                @cmd_sd_end:

@cmd_l:         cmp #'l'
                bne @cmd_l_end
                lda buffer+1

		cmp #'1'
		bne @cmd_l_test_2
                jsr cmd_loadimage
                jmp loop
		@cmd_l_test_2:
		cmp #'2'
		bne @cmd_l_test_3
                jsr cmd_loadimage
                jmp loop
		@cmd_l_test_3:
		cmp #'3'
		bne @cmd_l_end
		jsr cmd_loadimage_mc
                jmp loop
                @cmd_l_end:

@cmd_t:         cmp #'t'
                bne @cmd_t_end
                lda buffer+1

                cmp #'b'
                bne @cmd_t_test_w
                ; test converting an 8 bit number to BCD
                jsr cmd_test_bcd8
                jmp loop

                @cmd_t_test_w:
                cmp #'w'
                bne @cmd_t_test_k
                ; test converting a 16 bit number to BCD
                jsr cmd_test_bcd16
                jmp loop

;                @cmd_t_test_s:
;                cmp #'s'
;                bne @cmd_t_test_k
;                ;test playing a sound file
;                LDA #<TEST_VGM_DATA
;                STA R2
;                LDA #>TEST_VGM_DATA
;                STA R2+1
;                JSR snd_play_vgmdata
;                jmp loop

                @cmd_t_test_k:
.if .def(PS2K) || .def(VKEYB)
                cmp #'k'
                bne @cmd_t_test_K
                ; test keyboard
                JSR test_ps2_keyboard
                jmp loop

                @cmd_t_test_K:
                cmp #'K'
                bne @cmd_t_end
                ; test keyboard
                JSR test_ps2_keyboard_2
                jmp loop
.endif
                @cmd_t_end:

                ; h = print help
@cmd_h:         cmp #'h'
                bne @cmd_empty
                ld16 R0, msg_help
                jsr acia_puts
                jmp loop

                ; check for empty line - display prompt again
@cmd_empty:     cmp #$00
                bne @cmd_unknown
                jmp loop

                ; (fall through - unknown command)
@cmd_unknown:   ld16 R0, msg_unknown
                jsr acia_puts
                jmp loop

; ---------------------------------------------------------
; -- Strings 
prompt:     .byte "nam-mon-> ", $00
assign_arrow:   .byte " <- ", $00
.ifdef FASTCPU
    msg_welcome:    .byte "NAM-1 80K", $0d, $0a,"VDP Graphics 2.45MHz CPU",$0d,$0a, $00
.else
msg_welcome:    .byte "NAM-1 80K", $0d, $0a,"VDP Graphics",$0d,$0a, $00
.endif
msg_unknown:    .byte "Unknown command", $0d, $0a, $00
msg_help:       .byte "m <addr> - dump mem",$0d,$0a
                .byte "p <page> - dump page",$0d,$0a
                .byte "j <addr> - jmp",$0d,$0a
                .byte "w <addr> <byte> - write byte",$0d,$0a
                .byte "b - basic bw=warm start",$0d,$0a
                .byte "vd <page> - dump VRAM page",$0d,$0a
.ifdef PONG
                .byte "pp - play pong",$0d,$0a
.endif
.ifdef PACMAN
                .byte "pm - play pacman",$0d,$0a
.endif
                .byte $00
msg_error:      .byte "Error", $0d, $0a, $00
;msg_vdp_welcome:  .byte "Assif 6502 & EhBasic", $0d, $0a, $00

.if .def(PS2K)
msg_init_ps2k:
                .byte "PS2 "
.elseif .def(VKEYB)
msg_init_ps2k:
	.byte "Virtual PS2 "
.endif

msg_init_keyboard:
                .byte "Init keyboard",$0d,$0a,$00

; ---------------------------------------------------------
; -- execute commands
; Display a range of memory as hex numbers and characters
; m <start-address>
cmd_m_error:    ld16 R0, msg_error
                jsr acia_puts
                rts

cmd_memory: ; Check if only "m" or "m " was entered - address unchanged
                lda buffer + 1
                beq print_address
                lda buffer + 2
                beq print_address

                ; "m" and a not 4 digit address is a error
                lda buffer + 3
                beq cmd_m_error
                lda buffer + 4
                beq cmd_m_error
                lda buffer + 5
                beq cmd_m_error

                ; read the address
                ld16 R0, buffer + 2
                jsr scan_hex16
                LDA RES 
                STA R1
                LDA RES+1
                STA R1+1
print_address:  jsr print_memory16
                RTS

; Dump a page of CPU memory
cmd_dump_page:  LDA buffer+1
                CMP #' '
                BNE check_pong
                ld16 R0, buffer+2
                JSR scan_hex        ; scan 2 byte hex value into acc
                STA ZP_TMP0+1
                STZ ZP_TMP0
                JSR print_memory256
                RTS
; pp - play pong
check_pong:        
                CMP #'p'
                BNE check_pacman
.ifdef PONG
                JSR pong
.endif
                RTS
check_pacman:   CMP #'m'
		BNE check_breakout
.ifdef PACMAN
                JSR pacman
.endif
                RTS
check_breakout: CMP #'b'
                BNE cmd_m_error
.ifdef BREAKOUT
		JSR breakout
.endif
                RTS
                

; Write a byte to memory
; w <address> <byte>
cmd_write:      ld16 R0, buffer + 2
                jsr scan_hex16

@print_address: ld16 R0, buffer
                lda RES + 1
                jsr fmt_hex_string
                ld16 R0, buffer + 2
                lda RES
                jsr fmt_hex_string
                ld16 R0, buffer
                jsr acia_puts

                lda #':'
                jsr acia_putc

@read_and_print_byte: ld16 R0, buffer + 7
                jsr scan_hex
                tay
                ld16 R0, buffer
                tya
                jsr fmt_hex_string
                jsr acia_puts
                jsr acia_put_newline
                tya

@store_value:   ldy #0
                sta (RES),y
                rts

; Jump to address
; j <address>
cmd_jump:         ld16 R0, buffer + 2
                jsr scan_hex16

@print_address: lda #'*'
                jsr acia_putc
                ld16 R0, buffer
                lda RES + 1
                jsr fmt_hex_string
                ld16 R0, buffer + 2
                lda RES
                jsr fmt_hex_string
                ld16 R0, buffer
                jsr acia_puts
                jsr acia_put_newline

@jump:          jmp (RES)

;-----------------------------------------------------
; vd <page> - dump 256 bytes from <page> 
cmd_vram_dump:
                ld16 R0, buffer+3
                JSR scan_hex        ; scan 2 byte hex value into acc
                STA ZP_TMP0
                JSR vdp_dump_page
                RTS

; SD DIR command
cmd_dir:
                pha
                phx
                phy
                JSR fs_dir_root_start        ; Start at root
cd_dir_show_entry:
                CLC                            ; Only looking for valid files
                JSR fs_dir_find_entry        ; Find a valid entry
                BCS cd_dir_done                ; If C then no more entries so done
                JSR sdfs_set_dir_ptr        ; load addr of fh_dir into X(lo)A(hi)
                STX R0                        ; store them in string pointer so we can print
                STA R0+1
		JSR acia_puts_count         ; print string (file name)
                LDY R1                      ; number of chars printed is put into R1
                LDA #' '                    ; print spaces to pad to 14
cd_dir_pad:
                JSR acia_putc
                INY                            ; pad to 14 chars
                CPY #14
                BNE cd_dir_pad

                JSR sdfs_set_dir_filesize_ptr    ; put filesize into X/A
                JSR print_16bit_hex_string      ; print it
                jsr acia_put_newline

                JMP cd_dir_show_entry            ; Find another entry

cd_dir_done:
                CLC
                ply
                plx
                pla
                RTS

; print 4digit hex string from X/A A(hi)
; destroys buffer
print_16bit_hex_string:
                PHX
                PHA
                ld16 R0,buffer
                PLA
                JSR fmt_hex_string
                JSR acia_puts
                PLX
                TXA
                JSR fmt_hex_string
                JSR acia_puts
                RTS

;-----------------------------------------------------
; test bcd printing
cmd_test_bcd8:
                ld16 R0, buffer + 3
                JSR scan_hex               ; scan 2 character hex value into Acc
                JSR BINBCD8                ; convert to BCD and write in RES,RES+1
                ld16 R0, buffer            ; output buffer
                JSR BCD2STR                ; convert BCD to string
                JSR acia_puts              ; print it
                JSR acia_put_newline
                RTS
cmd_test_bcd16:
                ld16 R0, buffer + 3
                JSR scan_hex               ; scan 2 character hex value into Acc
                STA R1+1
                ld16 R0, buffer + 5
                JSR scan_hex               ; scan 2 character hex value into Acc
                STA R1
		JSR BINBCD16               ; convert to BCD and write in TMP0,TMP0+1,TMP1 (3bytes)
                ld16 R0, buffer            ; output buffer
                JSR BCD4BYTE2STR            ; convert BCD to string
                JSR acia_puts              ; print it
                JSR acia_put_newline
                RTS

;-----------------------------------------------------
; Load a compressed image (test)
cmd_loadimage:
.ifdef IMAGETEST
                ; switch to mode 2 (Screen2)
                LDA #2
                JSR vdp_set_mode
                ; put address into TMP1
                LDA #<image_smashmario_COMP
                STA TMP1
                LDA #>image_smashmario_COMP
                STA TMP1+1
                ; load image
                JSR decompRLE1_SC2
                RTS
image_smashmario_COMP:
    .include "smashmario_COMP.inc65"
.else
                RTS
.endif
cmd_loadimage_mc:
.ifdef IMAGETEST
		; switch to mode 3 (Multicolor)
                LDA #3
                JSR vdp_set_mode
                ; put address into TMP1
		LDA #<multicolor_test_data
                STA TMP1
                LDA #>multicolor_test_data
                STA TMP1+1
                ; load image
                JSR vdp_load_mc_pic
                RTS
    .include "mode3_example.inc65"
.else
                RTS
.endif

;-----------------------------------------------------
; run Basic - b[cw]
;
cmd_basic:        
                ; set JMP address for Cold boot (default)
                LDA #<LAB_COLD
                STA TMP0
                LDA #>LAB_COLD
                STA TMP0+1
                ; setup read from input string
                LDA buffer+1
                CMP #'w'
                BNE @boot_basic
                LDA #<LAB_WARM
                STA TMP0
                LDA #>LAB_WARM
                STA TMP0+1
@boot_basic:    JMP (TMP0)

.ifdef UCHESS2
;-----------------------------------------------------
; run Micro-Chess II by Peter Jennings/Daryl Richter
cmd_uchess2:
                JSR uchess2
                RTS
.endif

;-----------------------------------------------------
; BASIC linkage
;  - ROM code from LAB_vec to END_CODE will be copied to RAM $0300
;  - then there will be space for the Basic input buffer
;-----------------------------------------------------
;
; vector tables

LAB_vec:
        .word    CHARin        ; byte in from ACIA or Keyboard
        .word    CHARout        ; byte out to ACIA and video
;        .word    LOAD        ; load vector for EhBASIC
;        .word    SAVE        ; save vector for EhBASIC
; 4 bytes - replace with a real IRQ indirection vector
        JMP IRQ_CODE          ; 3 bytes - this will be labeled MY_IRQ_vec when  it gets copied to page 2

; EhBASIC IRQ support

IRQ_CODE:
        PHA                ; save A
        LDA    IrqBase        ; get the IRQ flag byte
        LSR                ; shift the set b7 to b6, and on down ...
        ORA    IrqBase        ; OR the original back in
        STA    IrqBase        ; save the new IRQ flag byte
        PLA                ; restore A
        RTI

; EhBASIC NMI support

NMI_CODE:
        PHA                ; save A
        LDA    NmiBase        ; get the NMI flag byte
        LSR                ; shift the set b7 to b6, and on down ...
        ORA    NmiBase        ; OR the original back in
        STA    NmiBase        ; save the new NMI flag byte
        PLA                ; restore A
        RTI

END_CODE:

; Output to serial & video
CHARout:
        CMP #$07
        BEQ DObell
        JSR ACIAout
        JSR vdp_write_char
;jsr acia_put_newline
        RTS

; Output only to serial port
ACIAout:
        PHA                ; A contains char to print
@wait_txd_empty:
        LDA ACIA_STATUS
        AND #ACIA_STATUS_TX_EMPTY
        BEQ @wait_txd_empty
        PLA                ; ready to output, restore A
        STA ACIA_DATA      ; and output
        RTS
        
; Input from ACIA and KBD if configured
CHARin:
        LDA ACIA_STATUS
        AND #ACIA_STATUS_RX_FULL
        BEQ @nobyw          ; branch if no byte waiting
        LDA ACIA_DATA
        AND #$7F            ; clear high bit
        SEC                 ; flag byte received
        RTS
@nobyw:
        CLC                 ; flag no byte received

.ifdef KEYB
        JSR kbd_scan
        BCC aciain_end
        LDA KBD_CHAR
        JMP aciain_end
.endif
.if .def(PS2K) || .def(VKEYB)
        jsr KBSCAN
        bcc aciain_nothing_waiting  ; C=0 means nothing waiting
        phx
        phy
        jsr KBINPUT                 ; there is something, decode to ASCII
        ply
        plx
        LDA KBD_CHAR
        BEQ aciain_nothing_waiting  ; 0 and $FF both mean nothing useful pressed
        CMP #$FF                    ; $FF is actually key release code
        BEQ aciain_nothing_waiting
;pha
;lda #'+'
;jsr acia_putc
;pla

        SEC
.endif

aciain_end:
        RTS
aciain_nothing_waiting:
        LDA #0
;pha
;lda #'.'
;jsr acia_putc
;pla
        CLC
        RTS
;------------------------------------
LOAD:
        RTS
SAVE:
        RTS

DObell:
        JSR snd_beep
        RTS

DObackspace:
        PHA
        JSR ANSI_BKSP
        PLA
        JSR vdp_backspace
        RTS
    
ANSI_BKSP:
        ; output ANSI "Cursor back"
        lda #$1b
        jsr ACIAout
        lda #'['
        jsr ACIAout
        lda #'D'
        jsr ACIAout
        lda #$1b
        jsr ACIAout
        lda #'['
        jsr ACIAout
        lda #'K'
        jsr ACIAout
        RTS

TEST_VGM_DATA:
; .include "BankPanic_GameStart.inc65"
;.include "KingsOfTheBeach_MatchSummary.inc65"
;.include "PingPong_Game_Entry.inc65"
