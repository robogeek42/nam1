;**********************************************************
;*
;*	DOLO-1 HOMEBREW COMPUTER
;*	Hardware and software design by Dolo Miah
;*	Copyright 2014-18
;*  Free to use for any non-commercial purpose subject to
;*  full credit of original my authorship please!
;*
;* modified by A. Mirza for ca65 and my own homebew NAM-1
;*
;*  SDCARD.S
;*  Low level SD card driver routines.  This module implements
;*  software bit banging through VIA 2 port B of an SD card
;*  interface.  So the card is clocked in software which is
;*  not great for performance but fast enough for my
;*  purposes.  I think we can get around 8.5KB/s raw sector
;*  read/write speed, translating to around 5.5KB/s of useful
;*  throughput using the filesystem.
;*
;**********************************************************

.setcpu "65C02"
.include "zeropage.inc65"
.include "io.inc65"
.include "acia.inc65"
.include "macros.inc65"
.include "string.inc65"
.include "print_util.inc65"

.export init_sdcard
;.export sd_sendcmd16
;.export sd_sendcmd17
;.export sd_sendcmd24
;.export sd_sendcmd41
;.export sd_sendcmd55

.export init_fs
.export sdfs_file_to_fh
.export sdfs_set_dir_ptr
.export sdfs_set_dir_filesize_ptr
.export fs_put_byte
.export fs_get_next_byte
.export fs_dir_root_start
.export fs_dir_find_entry
.export fs_delete
.export fs_open_read
.export fs_open_write
.export fs_close
.export msg_EOF

;* The FileHandle stucture is key to
;* accessing the file system
;* 40 bytes in total
	.struct FileHandle
		FH_Name .byte 13			; 8 name, 3 extension, 1 separator, 1 terminator
		FH_Size .byte 4
		FH_Attr .byte 1
		FH_CurrClust .byte 2
		FH_SectCounter .byte 1
		FH_CurrSec .byte 4
		FH_Pointer .byte 4
		FH_DirSect .byte 4
		FH_DirOffset .byte 2
		FH_FirstClust .byte 2
		FH_LastClust .byte 2
		FH_FileMode .byte 1
	.endstruct

SD_BUF = $7B

.segment "SDBUF"
sd_buf:
	.res 512,0

;.segment "INBUF"
;in_buf:
;    .res 256,0
;
;buf_lo = <in_buf
;buf_hi = >in_buf
;buf_sz = $FF
;buf_ef = $0D

.bss
charbuffer:
; File entry current dir entry
fh_handle:	.tag FileHandle
fh_dir:		.tag FileHandle

.export fh_handle
.export fh_dir
.export str_buf

;filesize_32bit:
;  .res 4,0    ; 4 bytes for a 32-bit number (file size)
str_buf:    .res 8,0

; ROM code
.code
msg_EOF: .byte "EOF",$0D,$0A,$00

;****************************************
;* long_delay
;* Long delay (X decremented every 0.125ms)
;* Input : X = number of 0.125ms ticks to wait (max wait approx 0.32s)
;*       : (assif: my homebrew runs at 1MHz, Dolo's at 2.68MHz
;*                 so this majes the X dec ~ 0.335ms
;* Output : None
;* Regs affected : None
;****************************************
long_delay:
	php
	pha
	phx
	phy
	
	ldy #$00
long_delay_1:
	nop
	nop
	nop
	nop
	dey
	bne long_delay_1
	dex
	bne long_delay_1

	ply
	plx
	pla
	plp
	
	rts

;****************************************
;* init_sdcard
;* Initialise SD card interface after VIA2!
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
init_sdcard:
	ld16 R0,sd_msg_initialising
	JSR acia_puts
init_retry:
    LDA #'.'
    JSR acia_putc

	lda #SD_CS						; Unselect device
	tsb SD_REG
	lda #SD_CLK						; Set clock low
	trb SD_REG
	lda #SD_MOSI					; DI/MOSI high
	tsb SD_REG
	ldx #3							; 3*0.335ms = 1ms
	jsr long_delay

	ldx #8							; 10 bytes of $ff
	lda #$ff
init_sd_pulse:
	jsr sd_sendbyte					; Send the $ff byte
	dex
	bne init_sd_pulse
	lda #SD_CS						; Unselect device
	tsb SD_REG

; Send command 0 (GO_IDLE_STATE. Read response, bit 0 set = Idle)
; R1 Response
; 	b7 b6 b5 b4 b3 b2 b1 b0
; 	0  |  |  |  |   | |  \ Idle
; 	   |  |  |  |   |  \ Erase reset
; 	   |  |  |  |   \ Illegal command
; 	   |  |  |  \ Command CRC Error
; 	   |  |  \ Erase sequence error
; 	   |  \ Address error
; 	    \ Parameter error
init_cmd0:
	jsr sd_sendcmd0					; GO_IDLE_STATE
	cmp #$ff						; $ff is not a valid response
	bne init_acmd41
    bra init_retry

; Send command 41 APP_SEND_OP_COND (Initiate initialisation process)
; needs CMD55 first as this is an APP command
; expect R1=0 (not idle)
init_acmd41:
    LDA #'+'
    JSR acia_putc

	jsr sd_sendcmd55
	jsr sd_sendcmd41
	
	cmp #0							; Was R1 = 0
	bne init_acmd41					; Retry if not
	
; Now can send command16 SET_BLOCKLEN
init_cmd16:
	jsr sd_sendcmd16

    ld16 R0,sd_msg_initdone
	JSR acia_puts

	rts

;****************************************
;* sd_startcmd
;* Start a cmd frame by sending CS high to low
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
sd_startcmd:
	pha
	lda #$ff						; Send $ff
	jsr sd_sendbyte					; Delay / synch pulses
	jsr sd_sendbyte					; With CS not asserted

	lda #SD_CS						; Chip select bit
	trb SD_REG						; Now set it low
	pla
	rts

;****************************************
;* sd_endcmd
;* End a cmd frame by sending CS high
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
sd_endcmd:
	pha
	lda #SD_CS						; Chip select bit
	tsb SD_REG						; First set it high
	pla
	rts

;****************************************
;* sd_sendbyte
;* Low level byte send routine
;* Input : A = byte to send
;* Output : None
;* Regs affected : None
;****************************************
sd_sendbyte:
	pha
	phy

	sta ZP_TMP2						; For shifting out
	ldy #8							; 8 bits to shift out
	lda SD_REG						; Load the SD register to A
sd_shiftoutbit:
	ora #SD_MOSI					; And initially set output bit to '1'
	asl ZP_TMP2						; Unless the bit to transmit is '0'
	bcs sd_shiftskiplo				; so then EOR the bit back to 0
	eor #SD_MOSI
sd_shiftskiplo:
	sta SD_REG						; Save data bit first, it seems, before clocking
	
	inc SD_REG
	dec SD_REG

	dey								; Count bits
	bne sd_shiftoutbit				; Until no more bits to send

	ply
	pla

	rts

;****************************************
;* sd_getbyte
;* Low level get a byte
;* Input : A = response byte received
;* Output : None
;* Regs affected : None
;****************************************

sd_getbyte:
	phy
	phx

	lda SD_REG
	ora #SD_MOSI					; Set MOSI high
	sta SD_REG
	tay								; Same as A with clock high
	iny
	tax								; Same as A with clock low
	
	; Unroll the code almost 20% faster than slow version
	; bit 7
	sty SD_REG
	lda SD_REG						; Sample SD card lines (MISO is the MSB)
	stx SD_REG
	cmp #SD_MISO					; Trial subtract A-MISO, C=1 if A >= MISO else C=0
	rol ZP_TMP2						; Rotate carry state in to ZP_TMP2
	; bit 6
	sty SD_REG
	lda SD_REG						; Sample SD card lines (MISO is the MSB)
	stx SD_REG
	cmp #SD_MISO					; Trial subtract A-MISO, C=1 if A >= MISO else C=0
	rol ZP_TMP2						; Rotate carry state in to ZP_TMP2
	; bit 5
	sty SD_REG
	lda SD_REG						; Sample SD card lines (MISO is the MSB)
	stx SD_REG
	cmp #SD_MISO					; Trial subtract A-MISO, C=1 if A >= MISO else C=0
	rol ZP_TMP2						; Rotate carry state in to ZP_TMP2
	; bit 4
	sty SD_REG
	lda SD_REG						; Sample SD card lines (MISO is the MSB)
	stx SD_REG
	cmp #SD_MISO					; Trial subtract A-MISO, C=1 if A >= MISO else C=0
	rol ZP_TMP2						; Rotate carry state in to ZP_TMP2
	; bit 3
	sty SD_REG
	lda SD_REG						; Sample SD card lines (MISO is the MSB)
	stx SD_REG
	cmp #SD_MISO					; Trial subtract A-MISO, C=1 if A >= MISO else C=0
	rol ZP_TMP2						; Rotate carry state in to ZP_TMP2
	; bit 2
	sty SD_REG
	lda SD_REG						; Sample SD card lines (MISO is the MSB)
	stx SD_REG
	cmp #SD_MISO					; Trial subtract A-MISO, C=1 if A >= MISO else C=0
	rol ZP_TMP2						; Rotate carry state in to ZP_TMP2
	; bit 1
	sty SD_REG
	lda SD_REG						; Sample SD card lines (MISO is the MSB)
	stx SD_REG
	cmp #SD_MISO					; Trial subtract A-MISO, C=1 if A >= MISO else C=0
	rol ZP_TMP2						; Rotate carry state in to ZP_TMP2
	; bit 0
	sty SD_REG
	lda SD_REG						; Sample SD card lines (MISO is the MSB)
	stx SD_REG
	cmp #SD_MISO					; Trial subtract A-MISO, C=1 if A >= MISO else C=0
	rol ZP_TMP2						; Rotate carry state in to ZP_TMP2

	lda ZP_TMP2						; Return response in A

	plx
	ply

	rts

;sd_getbyte							; OLD and SLOW version
;	phy
;
;	lda SD_REG
;	ora #SD_MOSI					; Set MOSI high
;	sta SD_REG
;	
;	ldy #8							; Shift in the 8 bits
;sd_shiftinbit
;	inc SD_REG
;	lda SD_REG						; Sample SD card lines (MISO is the MSB)
;	dec SD_REG
;	cmp #SD_MISO					; Trial subtract A-MISO, C=1 if A >= MISO else C=0
;	rol ZP_TMP2						; Rotate carry state in to ZP_TMP2
;	dey								; Next bit
;	bne sd_shiftinbit
;
;	lda ZP_TMP2						; Return response in A
;	
;	ply
;
;	rts

;****************************************
;* sd_getrespbyte
;* Low level get response routine
;* Input : A = response byte received
;* Output : None
;* Regs affected : None
;****************************************
sd_getrespbyte:
	phx
	ldx #0							; Try up to 256 times
sd_respff:
	inx								; Retry counter
	beq sd_resptimeout
	jsr sd_getbyte
	cmp #$ff						; Keep reading MISO until not FF
	beq sd_respff
sd_resptimeout:
	plx
	rts

;****************************************
;* sd_busy
;* Low level busy check routine
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
sd_busy:
	pha

;    ld16 R0,sd_msg_waitbusy
;	JSR acia_puts

sd_isbusy:
	jsr sd_getbyte
	cmp #$ff						; Keep reading MISO until FF
	bne sd_isbusy
;    ld16 R0,sd_msg_ready
;	JSR acia_puts
	pla
	rts

;****************************************
;* sd_waitforn0byte
;* Low level routine waits for card to be ready
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
sd_waitforn0byte:
	jsr sd_getrespbyte
	beq sd_waitforn0byte					; Zero byte means not ready
	rts

;****************************************
;* sd_sendcmd0
;* Send CMD0
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
sd_sendcmd0:
	jsr sd_startcmd

	; Send $40, $00, $00, $00, $00, $95
	lda #$40
	jsr sd_sendbyte
	lda #$00
	jsr sd_sendbyte
	jsr sd_sendbyte
	jsr sd_sendbyte
	jsr sd_sendbyte
	lda #$95						; Checksum needs to be right
	jsr sd_sendbyte

	jsr sd_getrespR1				; Get the response

	jsr sd_endcmd
	
	rts

;****************************************
;* sd_sendcmd55
;* Send CMD55
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
sd_sendcmd55:
	jsr sd_startcmd

	; Send $40+55, $00, $00, $00, $00, $95
	lda #$40+55
	jsr sd_sendbyte
	lda #$00
	jsr sd_sendbyte
	jsr sd_sendbyte
	jsr sd_sendbyte
	jsr sd_sendbyte
	lda #$95						; Checksum needs to be right
	jsr sd_sendbyte

	jsr sd_getrespR1				; Get the response

	jsr sd_endcmd
	
	rts

;****************************************
;* sd_sendcmd41
;* Send ACMD41
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
sd_sendcmd41:
	jsr sd_startcmd

	; Send $40+41, $00, $00, $00, $00, $95
	lda #$40+41
	jsr sd_sendbyte
	lda #$00
	jsr sd_sendbyte
	jsr sd_sendbyte
	jsr sd_sendbyte
	jsr sd_sendbyte
	lda #$95						; Checksum needs to be right
	jsr sd_sendbyte

	jsr sd_getrespR1				; Get the response

	jsr sd_endcmd
	
	rts

;****************************************
;* sd_sendcmd16
;* Send CMD16
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
sd_sendcmd16:
	jsr sd_startcmd

	; Send $40+16, $00, $00, $02, $00, $95
	lda #$40+16
	jsr sd_sendbyte
	lda #$00
	jsr sd_sendbyte
	jsr sd_sendbyte
	lda #$02						; $200 block size = 512 bytes
	jsr sd_sendbyte
	lda #$00
	jsr sd_sendbyte
	lda #$95						; Checksum needs to be right
	jsr sd_sendbyte

	jsr sd_getrespR1				; Get the response

	jsr sd_endcmd
	
	rts

;****************************************
;* sd_getrespR1
;* Low level get response R1
;* Input : A = response byte received
;* Output : None
;* Regs affected : None
;****************************************
sd_getrespR1:
	jsr sd_getrespbyte
	rts

;****************************************
;* sd_sendcmd17
;* Send CMD17
;* Input : sd_sect = 4 bytes of sector offset little endian
;* Output : None
;* Regs affected : None
;****************************************
sd_sendcmd17:
	phx
	pha								; A is the page to write to
	
;    ld16 R0,sd_msg_readsector
;	JSR acia_puts
;    ld16 R0,str_buf
;    LDX #3
;@loop:
;    LDA sd_sect,X
;    JSR fmt_hex_string
;    JSR acia_puts
;    DEX
;    BNE @loop
;    JSR acia_put_newline

	jsr sd_startcmd

	; Convert sector address to byte address
	; Sector address is little endian
	; Byte address is big endian
	stz sd_addr+3					; LSB of address is always 0
	lda sd_sect+0					; LSB of sector goes to address+1
	sta sd_addr+2					; Equivalent of * 256
	lda sd_sect+1
	sta sd_addr+1
	lda sd_sect+2
	sta sd_addr+0
	clc								; Now addr*2 so equiv to sect*512
	asl sd_addr+3
	rol sd_addr+2
	rol sd_addr+1
	rol sd_addr+0

sd_cmd17addr:
	; Send $40+17, $A3, $A2, $A1, $A0, $95
	lda #$40+17
	jsr sd_sendbyte
	lda sd_addr+0
	jsr sd_sendbyte
	lda sd_addr+1
	jsr sd_sendbyte
	lda sd_addr+2
	jsr sd_sendbyte
	lda sd_addr+3
	jsr sd_sendbyte
	lda #$95						; Checksum needs to be right
	jsr sd_sendbyte

	jsr sd_getrespbyte
	tax								; Save response in X for return

	pla								; Get the A param
	jsr sd_getrespR17				; Get the response

	jsr sd_busy						; Wait for card to be ready
	
	jsr sd_endcmd

	txa								; Restore the response byte
	plx
	
	rts

;****************************************
;* sd_getrespR17
;* Low level get response R17
;* Input : A = R1 response byte received
;* Output : None
;* Regs affected : None
;****************************************
sd_getrespR17:
	pha
	phy

;    ld16 R0,sd_msg_getresp17
;	JSR acia_puts

	sta ZP_TMP0+1					; Page to read in to
	stz ZP_TMP0						; Always a page boundary
sd_getrespR17token:
	jsr sd_getbyte					; Get a byte
	cmp #$fe						; Is it the token?
	bne sd_getrespR17token			; No

;            ld16 R0,charbuffer

	ldy #0							; read 1st 256 bytes
sd_getrespR17block1:
	jsr sd_getbyte					; get a byte
	sta (ZP_TMP0),y					; Save the byte

;            PHA
;            TYA
;            AND #$0F
;            BNE @over1
;            JSR acia_put_newline
;            TYA
;            JSR fmt_hex_string
;            JSR acia_puts
;            LDA #':'
;            JSR acia_putc
;            LDA #' '
;            JSR acia_putc
;   @over1:
;            PLA
;            JSR fmt_hex_string
;            JSR acia_puts
;            LDA #' '
;            JSR acia_putc

	iny								; Keep going
	bne sd_getrespR17block1			; Until all bytes read

	inc ZP_TMP0+1					; Next page
sd_getrespR17block2:
	jsr sd_getbyte					; get a byet
	sta (ZP_TMP0),y					; Save the byte

;            PHA
;            TYA
;            AND #$0F
;            BNE @over2
;            JSR acia_put_newline
;            TYA
;            JSR fmt_hex_string
;            JSR acia_puts
;            LDA #':'
;            JSR acia_putc
;            LDA #' '
;            JSR acia_putc
;   @over2:
;            PLA
;            JSR fmt_hex_string
;            JSR acia_puts
;            LDA #' '
;            JSR acia_putc

	iny								; Keep going
	bne sd_getrespR17block2			; Until all bytes read

;            ld16 R0,sd_msg_crc
;            JSR acia_puts

	jsr sd_getbyte					; CRC

;            JSR fmt_hex_string
;            ld16 R0,charbuffer
;            JSR acia_puts
;            LDA #' '
;            JSR acia_putc

	jsr sd_getbyte					; CRC
	
;            JSR fmt_hex_string
;            JSR acia_puts
;            LDA #' '
;            JSR acia_putc
;            JSR acia_put_newline

; Debug print of 1st page of SD buffer
;            LDA #SD_BUF
;            STA ZP_TMP0+1
;            STZ ZP_TMP0
;            JSR print_memory256
	ply
	pla

;            ld16 R0,sd_msg_endresp17
;            JSR acia_puts
	rts
	

;****************************************
;* sd_sendcmd24
;* Send CMD24
;* Input : sd_sect = 4 bytes of sector offset little endian
;* Output : None
;* Regs affected : None
;****************************************
sd_sendcmd24:
	phy
	pha

	jsr sd_startcmd

	; Convert sector address to byte address
	; Sector address is little endian
	; Byte address is big endian
	stz sd_addr+3					; LSB of address is always 0
	lda sd_sect+0					; LSB of sector goes to address+1
	sta sd_addr+2					; Equivalent of * 256
	lda sd_sect+1
	sta sd_addr+1
	lda sd_sect+3
	sta sd_addr+0
	clc								; Now addr*2 so equiv to sect*512
	asl sd_addr+3
	rol sd_addr+2
	rol sd_addr+1
	rol sd_addr+0

	; Send $40+24, $A0, $A1, $A2, $A3, $95
	lda #$40+24
	jsr sd_sendbyte
	lda sd_addr+0
	jsr sd_sendbyte
	lda sd_addr+1
	jsr sd_sendbyte
	lda sd_addr+2
	jsr sd_sendbyte
	lda sd_addr+3
	jsr sd_sendbyte
	lda #$95					; Checksum needs to be right
	jsr sd_sendbyte

	jsr sd_getrespbyte			; Get response

	jsr sd_getbyte
	
	lda #$fe					; Start of data token
	jsr sd_sendbyte

	pla							; Retrieve the address high byte
	sta ZP_TMP0+1
	stz ZP_TMP0					; Address is always page boundary

	ldy #00
sd_writeblock_1:					; Send first 256 bytes
	lda (ZP_TMP0), y
	jsr sd_sendbyte
	iny
	bne sd_writeblock_1
	inc ZP_TMP0+1				; Next page for second 256 bytes
sd_writeblock_2:					; Send second 256 bytes
	lda (ZP_TMP0), y
	jsr sd_sendbyte
	iny
	bne sd_writeblock_2

	lda #$aa					; Arbitrary CRC bytes
	jsr sd_sendbyte
	jsr sd_sendbyte

	jsr sd_getbyte				; Get data response byte
	pha							; Save it to return

sd_waitforwritecomplete:
	jsr sd_busy					; Wait for card to be ready
	
	jsr sd_endcmd				; Release the card

	pla
	ply
	rts

;======================================================================
; Filesystem
;======================================================================
;-----------------------------------------
; BASIC linkage - Assif
; copy filename string to filehandle - convert to upper case
sdfs_file_to_fh:
	ldy #0
_sdfs_copy_fn:
	lda (ZP_TMP2),y
    bmi _sdfs_terminate     ; if >127 then it is not a char - terminate
    beq _sdfs_terminate     ; if ==0 then it is not a char - terminate
    CMP #'"'
    beq _sdfs_terminate
    CMP #$21                ; space+1
    bcc _sdfs_terminate     ; non-printable - this is a filename

	bit #$40				; If 0x40 bit not set
	beq _sdfs_fname_case	; then not an alpha char
	and #$df				; Else mask out 0x20 bit to make upper case

_sdfs_fname_case:
	sta fh_handle,y
	iny
	cmp #0
	bne _sdfs_copy_fn
    
_sdfs_terminate:
    lda #0
    sta fh_handle,y         ; terminate with a zero
	rts

sdfs_set_dir_ptr:
    LDX #<fh_dir            ; low byte
    ;STX R0+1
    LDA #>fh_dir            ; hi byte
    ;STA R0
    ;JSR acia_puts
	RTS

sdfs_set_dir_filesize_ptr:
    ; put DIR offset by FH_Size into X(lo) A(hi)
    LDX fh_dir+FileHandle::FH_Size      ; Lo byte
    LDA fh_dir+FileHandle::FH_Size+1    ; Hi byte
	RTS
;-----------------------------------------

;****************************************
;* init_fs
;* Initialise filesystem - after sd card!
;* Input : None
;* Output : None
;* Regs affected : None
;****************************************
init_fs:
	ld16 R0, msg_initialising_fs
	JSR acia_puts

	ldx #$03					; Init sector to 0
init_fs_clr_sect:
	stz sd_sect,x
	dex
	bpl init_fs_clr_sect

	lda #SD_BUF				; Read in to the buffer
	jsr sd_sendcmd17			; Call read block

	;Extract data from boot record
	ldx #$03					; Assuming boot sector 0
init_fs_clr_boot:
	stz fs_bootsect,x
	dex
	bpl init_fs_clr_boot

	; Calculate start of FAT tables
	; Assumeing there are about 64k clusters
	; Each cluster assumed to be 32k sectors
	; Giving 64k x 32k x 0.5 ~ 1GB storage
	clc
	lda fs_bootsect
	adc sd_buf+MBR_ResvSect
	sta fs_fatsect
	lda fs_bootsect+1
	adc sd_buf+MBR_ResvSect+1
	sta fs_fatsect+1
	stz fs_fatsect+2		; Store Zero 65C02 instruction
	stz fs_fatsect+3
	
	; Calculate start of Root Directory
	lda sd_buf+MBR_SectPerFAT	; Initialise to 1 * SectPerFAT
	sta fs_rootsect
	lda sd_buf+MBR_SectPerFAT+1
	sta fs_rootsect+1
	clc							; Add again = *2
	lda sd_buf+MBR_SectPerFAT
	adc fs_rootsect
	sta fs_rootsect
	lda sd_buf+MBR_SectPerFAT+1
	adc fs_rootsect+1
	sta fs_rootsect+1
	stz fs_rootsect+2
	stz fs_rootsect+3

	; Now add FAT offset
	clc
	ldx #$00
	ldy #$04
fs_init_add_fat:
	lda fs_fatsect,x
	adc fs_rootsect,x
	sta fs_rootsect,x
	inx
	dey
	bne fs_init_add_fat
	
	; Calculate start of data area
	; Assuming 512 root dir entries!
	lda #1						; 512/512 = 1
	sta fs_datasect
	stz fs_datasect+1
	stz fs_datasect+2
	stz fs_datasect+3
	
	ldy #5						; Multiply by 32 to get root dir size in sectors
fs_rootmult1:
	clc
	asl fs_datasect
	rol fs_datasect+1
	rol fs_datasect+2
	rol fs_datasect+3
	dey
	bne fs_rootmult1

	; Now add root directory offset
	clc
	ldx #$00
	ldy #$04
fs_init_data:
	lda fs_rootsect,x
	adc fs_datasect,x
	sta fs_datasect,x
	inx
	dey
	bne fs_init_data

	sec							; Now subtract 2 clusters worth of sector
	lda fs_datasect+0			; to enable easy use of clusters in main
	sbc #$40					; FS handling routines
	sta fs_datasect+0			; Each cluster = 32 sectors
	lda fs_datasect+1			; Therefore take off $40 sectors from datasect
	sbc #0
	sta fs_datasect+1
	lda fs_datasect+2
	sbc #0
	sta fs_datasect+2
	lda fs_datasect+3
	sbc #0
	sta fs_datasect+3

	; Current directory = root dir
	ldx #$03
fs_init_dir_sect:
	lda fs_rootsect,x
	sta fs_dirsect,x
	dex
	bpl fs_init_dir_sect
	
	rts

;****************************************
;* fs_getbyte_sd_buf
;* Given a populated SD buffer, get byte
;* Indexed by X,Y (X=lo,Y=hi) 
;* Input : X,Y make 9 bit index
;* Output : A=Byte
;* Regs affected : None
;****************************************
fs_getbyte_sd_buf:
	tya
	and #1
	bne fs_getbyte_sd_buf_hi
	lda sd_buf,x
	rts
fs_getbyte_sd_buf_hi:
	lda sd_buf+$100,x
	rts

;****************************************
;* fs_putbyte_sd_buf
;* Given a populated SD buffer, put byte
;* Indexed by X,Y (X=lo,Y=hi), A=Val 
;* Input : X,Y make 9 bit index, A=byte
;* Output : None
;* Regs affected : None
;****************************************
fs_putbyte_sd_buf:
	pha
	tya
	and #1
	bne fs_putbyte_sd_buf_hi
	pla
	sta sd_buf,x
	rts
fs_putbyte_sd_buf_hi:
	pla
	sta sd_buf+$100,x
	rts

;****************************************
;* fs_getword_sd_buf
;* Given a populated SD buffer, get word
;* Indexed by Y which is word aligned 
;* Input : Y=Word offset in to sd_buf
;* Output : X,A=Word
;* Regs affected : None
;****************************************
fs_getword_sd_buf:
	tya
	asl a
	tax
	bcs fs_getword_sd_buf_hi
	lda sd_buf,x
	pha
	lda sd_buf+1,x
	plx
	rts
fs_getword_sd_buf_hi:
	lda sd_buf+$100,x
	pha
	lda sd_buf+$100+1,x
	plx
	rts

;****************************************
;* fs_putword_sd_buf
;* Given a populated SD buffer, put word
;* Indexed by Y which is word aligned 
;* Input : Y=Word offset in to sd_buf
;* Output : X,A=Word
;* Regs affected : None
;****************************************
fs_putword_sd_buf:
	phy
	pha
	phx
	tya
	asl a
	tay
	bcs fs_putword_sd_buf_hi
	pla
	tax
	sta sd_buf,y
	pla
	sta sd_buf+1,y
	ply
	rts
fs_putword_sd_buf_hi:
	pla
	tax
	sta sd_buf+$100,y
	pla
	sta sd_buf+$100+1,y
	ply
	rts


;****************************************
;* fs_dir_root_start
;* Initialise ready to read root directory
;* Input : dirsect is current directory pointer
;* Output : None
;* Regs affected : None
;****************************************
fs_dir_root_start:
	pha
	phx

	; Set SD sector to root directory
	ldx #$03
fs_dir_set_sd:
	lda fs_dirsect,x
	sta sd_sect,x
	dex
	bpl fs_dir_set_sd

	; SD buffer is where blocks will be read to
	stz sd_slo
	lda #SD_BUF
	sta sd_shi

	; Load up first sector in to SD buf
	lda #SD_BUF
	jsr sd_sendcmd17

	plx
	pla
	rts

;****************************************
;* fs_dir_find_entry
;* Read directory entry
;* Input : sd_slo, sd_shi : Pointer to directory entry in SD buffer
;* Input : C = 0 only find active files.  C = 1 find first available slot
;* Output : None
;* Regs affected : None
;****************************************
fs_dir_find_entry:
	pha
	phx
	phy
	php							; Save C state for checking later
fs_dir_check_entry:
	; Not LFN aware
	ldy #FAT_Attr				; Check attribute
	lda #$5e					; Any of H, S, V, D, I then skip
	and (sd_slo),y
	bne fs_dir_invalid_entry
	ldy #FAT_Name				; Examine 1st byte of name
	lda (sd_slo),y
	plp							; Check C
	php
	bcc	fs_find_active_slot		; Looking to find an active file
	cmp #0						; Else looking for 0 or $e5
	beq fs_dir_found_entry
	cmp #$e5
	beq fs_dir_found_entry
	bra fs_dir_invalid_entry	; Else not an entry we're interested in
fs_find_active_slot:
	cmp #0
	beq fs_dir_done				; If zero then no more entries
	cmp #$e5					; Deleted entry?
	bne fs_dir_found_entry
fs_dir_invalid_entry:
	jsr fs_dir_next_entry		; Advance read for next iteration
	bra fs_dir_check_entry

	; Found a valid entry or finished
fs_dir_done:						; No more entries
	plp							; Remove temp P from stack
	sec							; Set carry to indicate no more
	bra fs_dir_fin
fs_dir_found_entry:
	plp							; Remove temp P from stack
	jsr fs_dir_copy_entry		; Copy the important entry details
	jsr fs_dir_next_entry		; Advance read for next iteration
	clc							; Clear carry to indicate found
fs_dir_fin:						; Finalise
	ply
	plx
	pla
	rts
	
;****************************************
;* fs_dir_next_entry
;* Jump to next directory entry (32 bytes)
;* Load next sector if required
;* Input : sd_slo, sd_shi : Pointer to directory entry in SD buffer
;* Output : None
;* Regs affected : None
;****************************************
fs_dir_next_entry:
	pha
	phx
	phy
	
	clc							; Jump to next 32 byte entry
	lda sd_slo					; Update sd_slo, sd_shi
	adc #32
	sta sd_slo
	lda sd_shi
	adc #0
	sta sd_shi
    cmp #SD_BUF+2				; If not at end of sector (page 5) Assif: change to SDBUF+2 (512byte blocks)
	bne fs_dir_next_done		; then don't load next sector

	; Advance the sector
	ldx #$00
    ldy #$04                    ; Assif 4 byte word LSB first
    sec                         ; will increment first byte
fs_dir_inc_sect:
	lda sd_sect,x
    adc #0                      ; any carries will ripple
	sta sd_sect,x
	inx
	dey
	bne fs_dir_inc_sect
	
	; Reset SD buffer  where blocks will be read to
	stz sd_slo
	lda #SD_BUF
	sta sd_shi

	lda #SD_BUF				; Goes in to sd_buf
	jsr sd_sendcmd17			; Load it

fs_dir_next_done:
	ply
	plx
	pla
	rts
	

;****************************************
;* fs_dir_copy_entry
;* Copy directory entry
;* Input : sd_slo, sd_shi : Pointer to directory entry in SD buffer
;* Input : C = 0 for an active entry (copy loaded directory info)
;* Input : C = 1 for an empty entry (don't copy size, filename etc)
;* Output : None
;* Regs affected : None
;****************************************
fs_dir_copy_entry:
	pha
	phx
	phy
	bcs fs_dir_empty_slot		; If an empty slot, then most info not relevant

	;Normal processing of an entry loaded from the directory
	ldx #FileHandle::FH_Name	; Point to where name will go (X=>0)
    ldy #FAT_Name               ; offset into 32byte dir entry to find Name ($00)
fs_dir_get_name_ch:
	lda (sd_slo),y				; Get name char
	cmp #' '					; Don't copy space
	beq	fs_dir_skip_name_ch
	cpy #FAT_Ext				; At extension?
	bne fs_dir_skip_ext_ch
	pha							; Save A
	lda #'.'					; Inject '.'
	sta fh_dir,x				; Copy byte
	pla							; Restore A
	inx							; Advance
fs_dir_skip_ext_ch:
	sta fh_dir,x				; Copy byte
	inx							; Advance
fs_dir_skip_name_ch:
	iny							; Next SD dir entry
	cpy #FAT_Attr				; Passed end of name?
	bne fs_dir_get_name_ch	
fs_dir_entry_pad_name:
	cpx #FileHandle::FH_Size				; End of FH name space?
	beq fs_dir_entry_size		; Yes, then copy size
	stz fh_dir,x				; Else put 0
	inx
	bra fs_dir_entry_pad_name

fs_dir_entry_size:
	ldx #FileHandle::FH_Size				; Point to where size will go
	ldy #FAT_FileSize			; Point to get size from
	jsr fs_dir_util_copy		; Copy 4 bytes
	jsr fs_dir_util_copy
	jsr fs_dir_util_copy
	jsr fs_dir_util_copy
	
fs_dir_entry_attr:
	ldx #FileHandle::FH_Attr				; Point to where attributes go
	ldy #FAT_Attr				; Point from where to get attributes
	jsr fs_dir_util_copy		; Copy 1 byte

fs_dir_entry_clust:
	ldx #FileHandle::FH_FirstClust
	ldy	#FAT_FirstClust
	jsr fs_dir_util_copy		; Copy 2 bytes
	jsr fs_dir_util_copy

	; Empty slot data goes here
fs_dir_empty_slot:
fs_dir_entry_dirsect:			; Directory sector in which FH entry belongs
	ldx #$03
fs_dir_copy_sd_sect:
	lda sd_sect,x
	sta fh_dir+FileHandle::FH_DirSect,x
	dex
	bpl fs_dir_copy_sd_sect
	
fs_dir_entry_diroffset:			; Offset in to directory sector of FH entry
	lda sd_slo
	sta fh_dir+FileHandle::FH_DirOffset
	lda sd_shi
	sta fh_dir+FileHandle::FH_DirOffset+1
	
	ply
	plx
	pla
	
	rts
	

;****************************************
;* fs_dir_util_copy
;* Copy SD bytes to directory entry area
;* Input 	: y = offset in to sd directory
;*		 	: x = offset in to dir entry
;* Output 	: None
;* Regs affected : All
;****************************************
fs_dir_util_copy:
	pha
	lda (sd_slo),y
	sta fh_dir,x
	iny
	inx
	pla
	rts



;****************************************
;* fs_get_next_cluster
;* Given current cluster, find the next
;* Input : fh_handle
;* Output : 
;* Regs affected : None
;****************************************
fs_get_next_cluster:
	pha
	phx
	phy

	; Get the FAT sector that current clust is in
	jsr fs_get_FAT_clust_sect

	; Get next from this cluster index need low byte only
	; as each FAT cluster contains 256 cluster entries
	ldy fh_handle+FileHandle::FH_CurrClust
	; X = Low byte, A = High byte of cluster
	jsr fs_getword_sd_buf
	; Make this the current cluster
	stx fh_handle+FileHandle::FH_CurrClust
	sta fh_handle+FileHandle::FH_CurrClust+1
	
	; Calculate the sector address
	jsr fs_get_start_sect_data
	lda #$20					; 32 sector per cluster countdown			
	sta fh_handle+FileHandle::FH_SectCounter

	ply
	plx
	pla
	rts
	
;****************************************
;* fs_IsEOF
;* End of File check (compare file pointer to file size)
;* Input : fh_handle
;* Output : 
;* Regs affected : None
;****************************************
fs_isEOF:
	pha
	phx
	
	ldx #$03
fs_is_eof_cmp:
	lda fh_handle+FileHandle::FH_Pointer,x
	cmp fh_handle+FileHandle::FH_Size,x
	bne fs_notEOF
	dex
	bpl fs_is_eof_cmp

	plx
	pla
	sec							; C = 1 for EOF
	rts

fs_notEOF:	
	plx
	pla
	clc							; C = 0 for not EOF
	rts

	
;****************************************
;* fs_inc_pointer
;* Increment file point, loading sectors and clusters as appropriate
;* This results in sd_buf containing the sector that the pointer points to
;* Input : fh_handle
;* Output : 
;* Regs affected : None
;****************************************
fs_inc_pointer:
	pha
	phx
	phy
	
	;Increment pointer
	ldx #$00
	ldy #$04
	sec									; Always adds 1 first
fs_inc_fh_pointer:
	lda fh_handle+FileHandle::FH_Pointer,x
	adc #$00
	sta fh_handle+FileHandle::FH_Pointer,x
	inx
	dey
	bne fs_inc_fh_pointer

	lda fh_handle+FileHandle::FH_Pointer			; If low order == 0
	beq fs_inc_sector_ov				; Then sector 8 bits has overflowed
fs_inc_fin:
	ply
	plx
	pla
	
	rts
fs_inc_sector_ov:						; Check if sector bit 8 has overflowed
	lda fh_handle+FileHandle::FH_Pointer+1			; Load up next highest byte
	and #1								; If bit zero = 0 then must have
	bne fs_inc_fin						; overflowed.
	;Sector change required
	ldx #$00
	ldy #$04
	sec									; Always adds 1 first
fs_inc_fh_sect:
	lda fh_handle+FileHandle::FH_CurrSec,x
	adc #$00
	sta fh_handle+FileHandle::FH_CurrSec,x
	inx
	dey
	bne fs_inc_fh_sect
fs_inc_skip_sec_wrap:
	dec fh_handle+FileHandle::FH_SectCounter		; If reached the end of a cluster
	bne fs_inc_load_sector				; Then get next cluster
	; Cluster change required
	jsr fs_get_next_cluster				; Get next cluster based on current	
	jsr fs_load_curr_sect				; Load it
fs_inc_load_sector:
	jsr fs_isEOF						; Check not EOF
	bcs fs_skip_load_sect				; if so then don't load sector
	jsr fs_load_curr_sect				; Load the sector
fs_skip_load_sect:
	ply
	plx
	pla
	rts


	
;****************************************
;* fs_get_next_byte
;* Get a byte
;* Input : fh_handle
;* Output : A = char, C = 1 (EOF)
;* Regs affected : None
;****************************************
fs_get_next_byte:
	phx
	phy

	jsr fs_isEOF						; If at EOF then error
	bcc fs_get_skip_EOF

	;lda #FS_ERR_EOF
	;sta errno
	sec
	ply
	plx
	rts

fs_get_skip_EOF:
	ldx fh_handle+FileHandle::FH_Pointer			; Low 8 bits of sector index
	ldy fh_handle+FileHandle::FH_Pointer+1			; Which half of sector?
	; A=SD buffer byte
	jsr fs_getbyte_sd_buf
	jsr fs_inc_pointer					; Increment file pointers

	clc									; No error
	;stz errno
	ply
	plx
	rts
	


;****************************************
; Find the sector given the data cluster
; Given clust in LoX,HiA
; Outputs to fh_handle->FH_CurrSec
;****************************************
fs_get_start_sect_data:
	pha
	phx
	phy
	
	stx fh_handle+FileHandle::FH_CurrClust
	sta fh_handle+FileHandle::FH_CurrClust+1
	
	; Initialise to input sector
	stx fh_handle+FileHandle::FH_CurrSec+0
	sta fh_handle+FileHandle::FH_CurrSec+1
	stz fh_handle+FileHandle::FH_CurrSec+2
	stz fh_handle+FileHandle::FH_CurrSec+3
	
	; Sector = Cluster * 32
	; Shift left 5 times
	ldy #5
fs_get_data_sect_m5:
	clc
	asl fh_handle+FileHandle::FH_CurrSec+0
	rol fh_handle+FileHandle::FH_CurrSec+1
	rol fh_handle+FileHandle::FH_CurrSec+2
	rol fh_handle+FileHandle::FH_CurrSec+3
	dey
	bne fs_get_data_sect_m5

	; Add data sector offset
	ldx #$00
	ldy #$04
	clc
fs_get_start_data:
	lda fh_handle+FileHandle::FH_CurrSec,x
	adc fs_datasect,x
	sta fh_handle+FileHandle::FH_CurrSec,x
	inx
	dey
	bne fs_get_start_data

	ply
	plx
	pla
	rts
	
;****************************************
; Load the current sector in FH
;****************************************
fs_load_curr_sect:
	pha
	phx

	ldx #$03
fs_load_cpy_sect:
	lda fh_handle+FileHandle::FH_CurrSec,x
	sta sd_sect,x
	dex
	bpl fs_load_cpy_sect
	lda #SD_BUF
	jsr sd_sendcmd17

	plx
	pla
	rts

;****************************************
; Flush the current sector
;****************************************
fs_flush_curr_sect:
	pha
	phx

	ldx #$03
fs_flush_cpy_sect:
	lda fh_handle+FileHandle::FH_CurrSec,x
	sta sd_sect,x
	dex
	bpl fs_flush_cpy_sect
	lda #SD_BUF				; Sending data in sd_buf
	jsr sd_sendcmd24
	
	plx
	pla
	rts


;****************************************
;* fs_copy_dir_to_fh
;* Copy directory entry (fh) to file handle
;* Input : fh_dir contains directory entry
;* Output : None
;* Regs affected : None
;****************************************
fs_copy_dir_to_fh:
	pha
	phx
	ldx #FileHandle::FH_Name			; By default copy all
	bcc fs_copy_dir_to_fh_byte
	ldx #FileHandle::FH_Size			; But skip name if new file
fs_copy_dir_to_fh_byte:
	lda fh_dir,x
	sta fh_handle,x
	inx
	cpx #FileHandle::FH_FileMode+1		; copied last member?
	bne fs_copy_dir_to_fh_byte
	plx
	pla
	rts

;****************************************
;* fs_find_empty_clust
;* Find an empty cluster to write to
;* Input : None
;* Output : fh_handle->FH_CurrClust is the empty cluster
;* Regs affected : None
;****************************************
fs_find_empty_clust:
	pha
	phx
	phy

	; Starting at cluster $0002
	lda #02
	sta fh_handle+FileHandle::FH_CurrClust
	stz fh_handle+FileHandle::FH_CurrClust+1

	
	; Start at the first FAT sector
	ldx #$03
fs_find_init_fat:
	lda fs_fatsect,x
	sta fh_handle+FileHandle::FH_CurrSec,x
	dex
	bpl fs_find_init_fat

	; There is only enough room for 512/2 = 256 cluster entries per sector
	; There are 256 sectors of FAT entries

fs_check_empty_sector:
	jsr fs_load_curr_sect			; Load a FAT sector
fs_check_curr_clust:
	ldy fh_handle+FileHandle::FH_CurrClust		; Index in to this FAT sector
	jsr fs_getword_sd_buf
	cpx #0
	bne fs_next_fat_entry
	cmp #0
	bne fs_next_fat_entry
	
	; If got here then empty cluster found
	; fh_handle->FH_CurrClust is the empty cluster
	
	; Mark this cluster as used
	ldx #$ff
	lda #$ff
	jsr fs_putword_sd_buf

	; flush this FAT entry back so this cluster is safe from reuse
	jsr fs_flush_curr_sect
	
	stz fh_handle+FileHandle::FH_SectCounter	; Zero the sector count
	ldx fh_handle+FileHandle::FH_CurrClust
	lda fh_handle+FileHandle::FH_CurrClust+1
	jsr fs_get_start_sect_data		; Initialise the sector
	ply
	plx
	pla
	rts
	; If got here then need to find another cluster
fs_next_fat_entry:
	inc16 fh_handle+FileHandle::FH_CurrClust	; Increment the cluster number
	; Only 256 FAT entries in a sector of 512 bytes
	lda fh_handle+FileHandle::FH_CurrClust		; Check low byte of cluster number
	bne fs_check_curr_clust			; Else keep checking clusters in this sector
	; Every 256 FAT entries, need to get a new FAT sector
fs_next_fat_sect:
	jsr fs_inc_curr_sec				; Increment to the next FAT sector
	bra fs_check_empty_sector		; Go an load the new FAT sector and continue
	

;****************************************
;* fs_inc_curr_sec
;* Increment sector by 1
;* Input : fh_handle has the sector
;****************************************
fs_inc_curr_sec:
	pha
	phx
	phy
	
	; add 1 to LSB as sector address is little endian
	ldx #$00
	ldy #$04
	sec
fs_inc_sec_byte:
	lda fh_handle+FileHandle::FH_CurrSec,x
	adc #$00
	sta fh_handle+FileHandle::FH_CurrSec,x
	inx
	dey
	bne fs_inc_sec_byte

	ply
	plx
	pla
	rts
	

;****************************************
;* fs_get_FAT_clust_sect
;* Given FH_CurrClust, set FH_CurrSec so that
;* the sector contains the FAT entry
;* Input : fh_handle has the details
;* Output : None
;* Regs affected : None
;****************************************
fs_get_FAT_clust_sect:
	pha
	phx
	phy
	
	; Sector offset in to FAT = high byte
	; because a sector can hold 256 FAT entries
	lda fh_handle+FileHandle::FH_CurrClust+1
	sta fh_handle+FileHandle::FH_CurrSec
	stz fh_handle+FileHandle::FH_CurrSec+1
	stz fh_handle+FileHandle::FH_CurrSec+2
	stz fh_handle+FileHandle::FH_CurrSec+3
	
	; Add the FAT offset
	clc
	ldx #$00
	ldy #$04
fs_get_add_fat:
	lda fh_handle+FileHandle::FH_CurrSec,x
	adc fs_fatsect,x
	sta fh_handle+FileHandle::FH_CurrSec,x
	inx
	dey
	bne fs_get_add_fat

	; Now load the sector containing this cluster entry
	jsr fs_load_curr_sect

	ply
	plx
	pla
	rts
	
;****************************************
;* fs_update_FAT_entry
;* FH_LastClust updated with FH_CurrClust
;* Input : fh_handle has the details
;* Output : None
;* Regs affected : None
;****************************************
fs_update_FAT_entry:
	pha
	phx
	phy
	
	lda fh_handle+FileHandle::FH_CurrClust+0	; Save current cluster lo byte
	pha
	lda fh_handle+FileHandle::FH_CurrClust+1	; Save current cluster hi byte
	pha
	; Move back to the last cluster entry
	cpyword fh_handle+FileHandle::FH_LastClust,fh_handle+FileHandle::FH_CurrClust

	jsr fs_get_FAT_clust_sect		; Get the FAT sector to update
	; Index in to the FAT sector
	ldy fh_handle+FileHandle::FH_LastClust
	; Get current cluster hi,lo from stack
	pla
	plx
	; Update FAT entry Y with cluster X,A
	jsr fs_putword_sd_buf

	; The appropriate FAT sector has been updated
	; Now flush that sector back	
	jsr fs_flush_curr_sect
	
	; And restore the current cluster
	stx fh_handle+FileHandle::FH_CurrClust		; Make it the current cluster again
	sta fh_handle+FileHandle::FH_CurrClust+1	; Make it the current cluster again
	
	ply
	plx
	pla
	rts
	

;****************************************
;* fs_put_byte
;* Put out a byte, incrementing size
;* and committing clusters as necessary
;* including reflecting this in the FAT table
;* Input : fh_handle has the details, A = Byte to write
;* Output : None
;* Regs affected : None
;****************************************
fs_put_byte:
	phx
	phy
	pha

	; Before writing a byte, need to check if the current
	; sector is full.
	; Check low 9 bits of size and if zero size (i.e. 1st byte being put)
	lda fh_handle+FileHandle::FH_Size
	bne fs_put_do_put
	lda fh_handle+FileHandle::FH_Size+1
	beq fs_put_do_put
	and #1
	bne fs_put_do_put

	; We need to flush this sector to disk
	jsr fs_flush_curr_sect
	; Move to next sector in the cluster
	jsr fs_inc_curr_sec
	; Bump the sector counter
	inc fh_handle+FileHandle::FH_SectCounter
	; Check if counter at sectors per cluster limit
	lda fh_handle+FileHandle::FH_SectCounter
	cmp #$20
	bne fs_put_do_put
	; We need to find a new cluster now
	; But first update the FAT chain
	; so that the last cluster points to this
	jsr fs_update_FAT_entry
	; Before finding a new cluster
	; make the current the last
	cpyword fh_handle+FileHandle::FH_CurrClust,fh_handle+FileHandle::FH_LastClust
	; Go find a new empty clust
	; starts at sector 0
	jsr fs_find_empty_clust
	; Finally, can write a byte to the
	; SD buffer in memory
fs_put_do_put:	
	ldx fh_handle+FileHandle::FH_Size			; Load size low as index in to buffer
	ldy fh_handle+FileHandle::FH_Size+1			; Check which half
	pla								; Get A off stack and put back
	pha
	jsr fs_putbyte_sd_buf
fs_put_inc_size:
	sec
	ldx #$00
	ldy #$04
fs_put_inc_size_byte:
	lda fh_handle+FileHandle::FH_Size,x
	adc #0
	sta fh_handle+FileHandle::FH_Size,x
	inx
	dey
	bne fs_put_inc_size_byte
fs_put_fin:
	pla
	ply
	plx
	rts

;****************************************
;* fs_dir_save_entry
;* Save dir entry back to disk
;* Input : fh_handle has all the details
;* Output : None
;* Regs affected : None
;****************************************
fs_dir_save_entry:
	pha
	phx
	phy

	; Retrieve the sector where the file entry goes
	ldx #$03
fs_dir_curr_sect:
	lda fh_handle+FileHandle::FH_DirSect,x
	sta fh_handle+FileHandle::FH_CurrSec,x
	dex
	bpl fs_dir_curr_sect
	
	jsr fs_load_curr_sect

	; Restore index in to the correct entry
	lda fh_handle+FileHandle::FH_DirOffset
	sta sd_slo
	lda fh_handle+FileHandle::FH_DirOffset+1
	sta sd_shi
	
	;Save the filename
	ldx #FileHandle::FH_Name				; Point to where name will go
	ldy #FAT_Name
fs_dir_save_name_ch:
	lda fh_handle,x				; Get a char
	beq fs_dir_name_done		; If zero then name done
	cmp #'.'					; Is it '.'
	bne fs_dir_name_skip		; If so then don't consider
	inx							; Jump over '.'
	bra fs_dir_name_done		; and start processing the ext
fs_dir_name_skip:
	cpy #FAT_Ext				; Reached the end of the name?
	beq fs_dir_name_done
	sta (sd_slo),y				; No, so store the byte in name
	inx
	iny
	bra fs_dir_save_name_ch
fs_dir_name_done:
	
	lda #' '					; Pad name with spaces
fs_dir_pad_name:
	cpy #FAT_Ext				; Padded enough?
	beq fs_dir_pad_name_done
	sta (sd_slo),y				; Fill with space
	iny
	bra fs_dir_pad_name
fs_dir_pad_name_done:
	
fs_dir_save_ext_ch:
	cpy #FAT_Attr				; End of extension?
	beq fs_dir_ext_done
	lda fh_handle,x				; Get a char
	beq fs_dir_ext_done			; If zero then name done
	sta (sd_slo),y
	inx
	iny
	bra fs_dir_save_ext_ch	
fs_dir_ext_done:
	
	lda #' '					; Pad out any remaining with space
fs_dir_ext_pad:
	cpy #FAT_Attr				; Reached the end of the extension?
	beq fs_dir_ext_pad_done
	sta (sd_slo),y
	iny
	bra fs_dir_ext_pad
	; At the Attribute byte, zero out everything until size
fs_dir_ext_pad_done:
	
	lda #0
fs_dir_save_rest_ch:
	sta (sd_slo),y
	iny
	cpy #FAT_FirstClust
	bne fs_dir_save_rest_ch
	; Now save first cluster
	lda fh_handle+FileHandle::FH_FirstClust
	sta (sd_slo),y
	iny
	lda fh_handle+FileHandle::FH_FirstClust+1
	sta (sd_slo),y
	iny

	; Now save size
	ldx #0
df_dir_save_size_ch:
	lda fh_handle+FileHandle::FH_Size,x
	sta (sd_slo),y
	iny
	inx
	cpx #4
	bne df_dir_save_size_ch

	; Ok done copying data to directory entry
	; Now flush this back to disk
	
	jsr fs_flush_curr_sect
	
	; Phew we are done
	ply
	plx
	pla
	rts
	
	
;****************************************
;* fs_open_read
;* Open a file for reading
;* Input : fh_handle has the name
;* Output : None
;* Regs affected : None
;****************************************
fs_open_read:
	pha
	phx
	phy

            ; debug - print name from filehandle
            ld16 R0,sd_msg_find_file
            JSR acia_puts
            LDA #<fh_handle
            STA R0
            LDA #>fh_handle
            STA R0+1
            JSR acia_puts
            JSR acia_put_newline

	jsr fs_dir_root_start		; Start at root
fs_open_find:
	clc							; Only look for active files
	jsr fs_dir_find_entry		; Find a valid entry
	bcs	fs_open_not_found		; If C then no more entries

            ; Debug - print dir entry name
            LDA #<fh_dir
            STA R0
            LDA #>fh_dir
            STA R0+1
            JSR acia_puts
            JSR acia_put_newline
            
	ldx #0						; Check name matches
fs_open_check_name:
	lda fh_handle,x
    
    ; fh_handle is in upper case - convert the directory entry too
	bit #$40				; If 0x40 bit not set
    beq @notalpha       	; then not an alpha char
	and #$df				; Else mask out 0x20 bit to make upper case
@notalpha:

	cmp fh_dir,x
	bne fs_open_find
	cmp #0						; If no more bytes in name to check
	beq fs_open_found
	inx
	bra fs_open_check_name
fs_open_found:
	jsr fs_copy_dir_to_fh		; Put entry in to fh_handle

            ; Debug
            ld16 R0, sd_msg_found_entry
            JSR acia_puts
            JSR acia_put_newline

	lda #$20					; 32 sector per cluster countdown			
	sta fh_handle+FileHandle::FH_SectCounter

	ldx fh_handle+FileHandle::FH_FirstClust	; Load up first cluster
	lda fh_handle+FileHandle::FH_FirstClust+1

	jsr fs_get_start_sect_data	; Calc the first sector
	jsr fs_load_curr_sect		; Load it in to sd_buf


	ldx #$03					; Initialise pointer to beginning
fs_open_init_pointer:
	stz fh_handle+FileHandle::FH_Pointer,x
	dex
	bpl fs_open_init_pointer

	; Set file mode to read
	lda #$00
	sta fh_handle+FileHandle::FH_FileMode

	clc
fs_open_not_found:
	ply
	plx
	pla
	rts

; Print string pointed to by X(lo)&A(Hi)
; Y has number of chars printed
sdfs_printstr:
    STX TMP1
    STA TMP1+1
    LDY #0
fps_loop:
    LDA (TMP1),Y
    BEQ fps_done        ; char 00 = stop
    JSR acia_putc
	INY
    BEQ fps_done        ; printed 256 chars - stop anyway
    JMP fps_loop
fps_done:    
    RTS


;****************************************
;* fs_open_write
;* Open a file for writing
;* Input : fh_handle has the name
;*		 : existing file will overwritten
;*		 : new file will be created
;* Output : None
;* Regs affected : None
;****************************************
fs_open_write:
	pha
	phx
	phy

	; try and delete any file with the same name first
	lda fh_handle+FileHandle::FH_Name		; save first char as it gets deleted
	pha
	jsr fs_delete				; now delete it
	pla							; restore first char
	sta fh_handle+FileHandle::FH_Name
	jsr fs_dir_root_start		; Start at root
	sec							; Find an empty file entry
	jsr fs_dir_find_entry		; Find a valid entry
	bcs	fs_open_write_fin		; Error, didn't find!
	sec
	jsr fs_copy_dir_to_fh		; Copy entry to file handle

	stz fh_handle+FileHandle::FH_Size+0		; Size is zero initially
	stz fh_handle+FileHandle::FH_Size+1
	stz fh_handle+FileHandle::FH_Size+2
	stz fh_handle+FileHandle::FH_Size+3

	jsr fs_find_empty_clust		; Where will be the first cluster

	; Set current, last and first cluster
	lda fh_handle+FileHandle::FH_CurrClust
	sta fh_handle+FileHandle::FH_FirstClust
	sta fh_handle+FileHandle::FH_LastClust
	lda fh_handle+FileHandle::FH_CurrClust+1
	sta fh_handle+FileHandle::FH_FirstClust+1
	sta fh_handle+FileHandle::FH_LastClust+1

	; Set file mode to write
	lda #$ff
	sta fh_handle+FileHandle::FH_FileMode

	clc
fs_open_write_fin:
	ply
	plx
	pla
	rts


;****************************************
;* fs_close
;* Close a file, only important for new files
;* Input : fh_handle details
;* Output : None
;* Regs affected : None
;****************************************
fs_close:
	pha

	; Only need to close down stuff in write mode
	lda fh_handle+FileHandle::FH_FileMode
	beq fs_close_done
	
	; Flush the current sector
	jsr fs_flush_curr_sect

	; Update the chain from the last cluster
	jsr fs_update_FAT_entry

	; Make current sector = last
	lda fh_handle+FileHandle::FH_CurrClust
	sta fh_handle+FileHandle::FH_LastClust
	lda fh_handle+FileHandle::FH_CurrClust+1
	sta fh_handle+FileHandle::FH_LastClust+1
	; Need to update the FAT entry
	; to show this cluster is last
	lda #$ff
	sta fh_handle+FileHandle::FH_CurrClust
	sta fh_handle+FileHandle::FH_CurrClust+1
	; Now update the FAT entry to mark the last cluster

	jsr fs_update_FAT_entry

	jsr fs_dir_save_entry

fs_close_done:
	pla
	rts

;****************************************
;* fs_delete
;* Delete a file
;* Input : fh_handle has the name
;* Output : None
;* Regs affected : None
;****************************************
fs_delete:
	pha
	phx
	phy

	jsr fs_open_read			; Try and open the file
	bcs fs_delete_fin			; If not found then fin
	
	; Mark first char with deleted indicator
	lda #$e5
	sta fh_handle+FileHandle::FH_Name

	; Save this back to directory table
	jsr fs_dir_save_entry

	; Now mark all related clusters as free
	ldx fh_handle+FileHandle::FH_FirstClust
	stx fh_handle+FileHandle::FH_CurrClust
	ldy fh_handle+FileHandle::FH_FirstClust+1
	sty fh_handle+FileHandle::FH_CurrClust+1
fs_delete_clust:
	; X and Y always contain current cluster
	; Make last = current
	stx fh_handle+FileHandle::FH_LastClust
	sty fh_handle+FileHandle::FH_LastClust+1

	; Given current cluster, find next
	; save in X,Y
	jsr fs_get_next_cluster
	; load X,Y with the next cluster
	ldx fh_handle+FileHandle::FH_CurrClust
	ldy fh_handle+FileHandle::FH_CurrClust+1
	
	; Zero out the cluster number
	stz fh_handle+FileHandle::FH_CurrClust
	stz fh_handle+FileHandle::FH_CurrClust+1

	; Update FAT entry of Last Cluster with zero
	jsr fs_update_FAT_entry

	; Restore the next cluster found earlier
	stx fh_handle+FileHandle::FH_CurrClust
	sty fh_handle+FileHandle::FH_CurrClust+1

	; If the next cluster is not $ffff
	; then continue
	cpx #$ff
	bne fs_delete_clust
	cpy #$ff
	bne fs_delete_clust
	clc
fs_delete_fin:
	ply
	plx
	pla
	rts

;======================================================================
; I/O Routines (read/write line)
;======================================================================



;****************************************
;* Get a line of input
;* Output: C=0 means io_buf is valid
;****************************************
;sdfs_inputline:
;	; C is set on input for echo or not
;	; Read a line of input
;	jsr io_read_line
;	; If nothing entered then sec
;	cpy #0
;    bne sdfs_inputline_ok
;	sec
;	rts
;sdfs_inputline_ok:
;	clc
;	rts

;****************************************
;* io_read_line
;* Read a line, terminated by terminating char or max buffer length
;* Input : buf_(lo/hi/sz/ef) : Address, Max size, end marker, C = 1 means echo
;* Output : Y = Line length C = Buffer limit reached
;* Regs affected : None
;****************************************
;io_read_line:
;	pha
;
;	ldy #0x00			; Starting at first byte
;io_get_line_byte:
;    jsr fs_get_next_byte		; Get a byte
;	sta (buf_lo),y		; Save it
;	iny					; Increase length
;io_skip_special:
;	cmp buf_ef			; Is it the terminating char?
;	beq io_get_line_done	; If yes then done
;	cpy buf_sz			; Reached the buffer max size?
;	bne io_get_line_byte	; No, get another byte
;	sec					; Yes, set carry flag
;	pla
;	rts					; And done
;io_get_line_done:
;	lda #0
;	sta (buf_lo),y		; Terminate with 0
;	clc					; Clear carry flag
;	pla
;	rts					; Fin

;****************************************
;* io_write_line
;* Put a line of bytes out of a certain length
;* Input : buf_(lo/hi/sz/ef) : Address, Y=Max size
;* Output : None
;* Regs affected : All
;****************************************
;io_write_line
;	phy
;	pha
;	
;	ldy #0				; Start at first byte
;write_line_byte
;	cpy buf_sz			; Check first if buffer sized reached
;	beq write_line_done	; to catch zero length outputs
;	lda (buf_lo),y		; Read the byte
;	jsr io_put_ch		; Transmit
;	iny					; Ready for next byte
;	bne write_line_byte	; Forced branch as Y will only be 0 on wrap
;write_line_done
;
;	pla
;	ply
;	rts	


sd_msg_initialising:
	.byte "Initialising SD Card ",$00
sd_msg_initdone:
    .byte " done.", $0D,$0A,$00
;sd_msg_startcmd
;        .byte "Start cmd",$0D,$0A,$00
;sd_msg_getresp
;        .byte "Get resp",$0D,$0A,$00
;sd_msg_getresp17
;        .byte "Get resp17",$0D,$0A,$00
;sd_msg_waitbusy
;        .byte "Wait busy ... ",$00
;sd_msg_ready
;        .byte "ready",$0D,$0A,$00
;sd_msg_crc
;        .byte "crc",$0D,$0A,$00
;sd_msg_endresp17
;        .byte "EndResp17",$0D,$0A,$00
;sd_msg_backinsend17
;        .byte "back",$0D,$0A,$00
sd_msg_find_file:
        .byte "Find file ",$00
sd_msg_found_entry:
        .byte "found file",$0D,$0A,$00
sd_msg_readsector:
    .byte "Sector:",$00

sd_cmd55:
	.byte ($40+55), $00, $00, $00, $00, $95
sd_cmd58:
	.byte ($40+58), $00, $00, $00, $00, $95
sd_acmd41:
	.byte ($40+41), $00, $00, $00, $00, $95
	
	
msg_initialising_fs:
	.byte "Initialising filesystem",$0D,$0A,$00
fs_msg_directory_listing:
	.byte "SD Card Directory",$0D,$0A,$00

