; vim: ts=4 et sw=4
.setcpu "65C02"
.include "zeropage.inc65"
.include "macros.inc65"
.include "io.inc65"
.include "acia.inc65"
.include "string.inc65"
.include "scancodes.inc65"


;****************************************************************************
; PC keyboard Interface for the 6502 Microprocessor utilizing a 6522 VIA
; (or suitable substitute)
;
; Designed and Written by Daryl Rictor (c) 2001   65c02@altavista.com
; Offered as freeware.  No warranty is given.  Use at your own risk.
;
; Software requires about 930 bytes of RAM or ROM for code storage and only 4 bytes
; in RAM for temporary storage.  Zero page locations can be used but are NOT required.
;
; Hardware utilizes any two bidirection IO bits from a 6522 VIA connected directly 
; to a 5-pin DIN socket (or 6 pin PS2 DIN).  In this example I'm using the 
; 6526 PB4 (Clk) & PB5 (Data) pins connected to a 5-pin DIN.  The code could be
; rewritten to support other IO arrangements as well.  
; ________________________________________________________________________________
;|                                                                                |
;|        6502 <-> PC Keyboard Interface Schematic  by Daryl Rictor (c) 2001      |
;|                                                     65c02@altavista.com        |
;|                                                                                |
;|                                                           __________           |
;|                      ____________________________________|          |          |
;|                     /        Keyboard Data            15 |PB5       |          |
;|                     |                                    |          |          |
;|                _____|_____                               |          |          |
;|               /     |     \                              |   6522   |          |
;|              /      o      \    +5vdc (300mA)            |   VIA    |          |
;|        /-------o    2    o--------------------o---->     |          |          |
;|        |   |    4       5    |                |          |          |          |
;|        |   |                 |          *C1 __|__        |          |          |
;|        |   |  o 1       3 o  |              _____        |          |          |
;|        |   |  |              |                |          |          |          |
;|        |    \ |             /               __|__        |          |          |
;|        |     \|     _      /                 ___         |          |          |
;|        |      |____| |____/                   -          |          |          |
;|        |      |                  *C1 0.1uF Bypass Cap    |          |          |
;|        |      |                                          |          |          |
;|        |      \__________________________________________|          |          |
;|        |                    Keyboard Clock            14 | PB4      |          |
;|      __|__                                               |__________|          |
;|       ___                                                                      |
;|        -                                                                       |
;|            Keyboard Socket (not the keyboard cable)                            |
;|       (As viewed facing the holes)                                             |
;|                                                                                |
;|________________________________________________________________________________|
; 
; Software communicates to/from the keyboard and converts the received scan-codes
; into usable ASCII code.  ASCII codes 01-7F are decoded as well as extra 
; pseudo-codes in order to acess all the extra keys including cursor, num pad, function,
; and 3 windows 98 keys.  It was tested on two inexpensive keyboards with no errors.
; Just in case, though, I've coded the <Ctrl>-<Print Screen> key combination to perform
; a keyboard re-initialization just in case it goes south during data entry.
; 
; Recommended Routines callable from external programs
;
; KBINPUT - wait for a key press and return with its assigned ASCII code in A.
.export KBINPUT
; KBSCAN  - Scan the keyboard for 105uS, returns 0 in A if no key pressed.
;           Return ambiguous data in A if key is pressed.  Use KBINPUT OR KBGET
;           to get the key information.  You can modify the code to automatically 
;           jump to either routine if your application needs it.          
.export KBSCAN
; KBINIT  - Initialize the keyboard and associated variables and set the LEDs
.export KBINIT
; special KBSCAN for games that need make/break events
.export KBSCAN_GAME
; KBGET   - wait for a key press and return with its unprocessed scancode in A.
.export KBGET

.export KBTMON
.export KBTMOFF
;
;****************************************************************************
;
; All standard keys and control keys are decoded to 7 bit (bit 7=0) standard ASCII.
; Control key note: It is being assumed that if you hold down the ctrl key,
; you are going to press an alpha key (A-Z) with it (except break key defined below.)
; If you press another key, its ascii code's lower 5 bits will be send as a control
; code.  For example, Ctrl-1 sends $11, Ctrl-; sends $2B (Esc), Ctrl-F1 sends $01.
;
; The following no-standard keys are decoded with bit 7=1, bit 6=0 if not shifted,
; bit 6=1 if shifted, and bits 0-5 identify the key.
; 
; Function key translation:  
;              ASCII / Shifted ASCII
;            F1 - 81 / C1
;            F2 - 82 / C2
;            F3 - 83 / C3
;            F4 - 84 / C4
;            F5 - 85 / C5
;            F6 - 86 / C6
;            F7 - 87 / C7
;            F8 - 88 / C8
;            F9 - 89 / C9
;           F10 - 8A / CA
;           F11 - 8B / CB
;           F12 - 8C / CC
;
; The Print screen and Pause/Break keys are decoded as:
;                ASCII  Shifted ASCII
;        PrtScn - 8F       CF
;   Ctrl-PrtScn - performs keyboard reinitialization in case of errors 
;                (haven't had any yet)  (can be removed or changed by user)
;     Pause/Brk - 03       03  (Ctrl-C) (can change to 8E/CE)(non-repeating key)
;    Ctrl-Break - 02       02  (Ctrl-B) (can be changed to AE/EE)(non-repeating key)  
;      Scrl Lck - 8D       CD  
;
; The Alt key is decoded as a hold down (like shift and ctrl) but does not
; alter the ASCII code of the key(s) that follow.  Rather, it sends
; a Alt key-down code and a seperate Alt key-up code.  The user program
; will have to keep track of it if they want to use Alt keys. 
;
;      Alt down - A0
;        Alt up - E0
;
; Example byte stream of the Alt-F1 sequence:  A0 81 E0.  If Alt is held down longer
; than the repeat delay, a series of A0's will preceeed the 81 E0.
; i.e. A0 A0 A0 A0 A0 A0 81 E0.
;
; The three windows 98 keys are decoded as follows:
;                           ASCII    Shifted ASCII
;        Left Menu Key -      A1          E1 
;       Right Menu Key -      A2          E2
;     Right option Key -      A3          E3
;
; The following "special" keys ignore the shift key and return their special key code 
; when numlock is off or their direct labeled key is pressed.  When numlock is on, the digits
; are returned reguardless of shift key state.        
; keypad(NumLck off) or Direct - ASCII    Keypad(NumLck on) ASCII
;          Keypad 0        Ins - 90                 30
;          Keypad .        Del - 7F                 2E
;          Keypad 7       Home - 97                 37
;          Keypad 1        End - 91                 31
;          Keypad 9       PgUp - 99                 39
;          Keypad 3       PgDn - 93                 33
;          Keypad 8    UpArrow - 98                 38
;          Keypad 2    DnArrow - 92                 32
;          Keypad 4    LfArrow - 94                 34
;          Keypad 6    RtArrow - 96                 36 
;          Keypad 5    (blank) - 95                 35
;
;****************************************************************************
;
; I/O Port definitions

;kbportreg      =     $7f01             ; 6522 IO port register B
;kbportddr      =     $7f03             ; 6522 IO data direction register B
clk            =     $10               ; 6522 IO port clock bit mask (PB4)
data           =     $20               ; 6522 IO port data bit mask  (PB5)
kbportreg      =  VIA1 + VIA_IRB       ; 6522 IO port register B
kbportddr      =  VIA1 + VIA_DDRB      ; 6522 IO data direction register B
;clk            =  PS2K_CLK             ; 6522 IO port clock bit mask (PB1)
;data           =  PS2K_DAT             ; 6522 IO port data bit mask  (PB2)

; NOTE: some locations use the inverse of the bit masks to change the state of 
; bit.  You will have to find them and change them in the code acordingly.
; To make this easier, I've placed this text in the comment of each such statement:
; "(change if port bits change)" 
;
;
; temportary storage locations (zero page can be used but not necessary)

.bss
ps2k_vars: .res 4,0
byte           =    ps2k_vars          ; byte send/received
parity         =    ps2k_vars +1       ; parity holder for rx
special        =    ps2k_vars +2       ; ctrl, shift, caps and kb LED holder 
lastbyte       =    ps2k_vars +3       ; last byte received
sbuf: .res 10,0

; bit definitions for the special variable
; (1 is active, 0 inactive)
; special =  01 - Scroll Lock
;            02 - Num Lock
;            04 - Caps lock
;            08 - control (either left or right)
;            10 - shift  (either left or right)
;
;            80 - last code was a break code
;
;            Scroll Lock LED is used to tell when ready for input 
;                Scroll Lock LED on  = Not ready for input
;                Scroll Lock LED off = Waiting (ready) for input
;
;            Num Lock and Caps Lock LED's are used normally to 
;            indicate their respective states.

; commands
KBCMD_RESET     = $FF ; Rest
KBCMD_RESEND    = $FE ; Resend
KBCMD_SETKEYM   = $FD ; Set key type to Make 
KBCMD_SETKEYMB  = $FC ; Set key type to Make/Break
KBCMD_SETKEYT   = $FB ; Set key type to Typematic
KBCMD_SETALLTMB = $FA ; Set all keys to Typematic/Make/Break
KBCMD_SETALLM   = $F9 ; Set all keys to Make
KBCMD_SETALLMB  = $F8 ; Set all keys to Make/Break
KBCMD_SETALLT   = $F7 ; Set All Keys Typematic
KBCMD_SETDEF    = $F6 ; Load default typematic rate/delay (10.9cps / 500ms), key types (all keystypematic/make/break), and scan code set (2).
KBCMD_DISABLE   = $F5 ; Keyboard stops scanning, loads default values, and waits for further commands
KBCMD_ENABLE    = $F4 ; Re-enables keyboard after disabled using previous command.
KBCMD_SETDELAY  = $F3 ; Set Typematic Rate/Delay
KBCMD_READID    = $F2 ;
KBCMD_SETSCSET  = $F0 ; Set scan code set
KBCMD_ECHO      = $EE ; Echo
KBCMD_LEDS      = $ED ; Set/reset LEDs
; responses
KB_ACK          = $FA


;***************************************************************************************
;
; test program - reads input, prints the ascii code to the terminal and loops until the
; target keyboard <Esc> key is pressed.
;
; external routine "output" prints character in A to the terminal
; external routine "print1byte" prints A register as two hexidecimal characters
; external routine "print_cr" prints characters $0D & $0A to the terminal
; (substitute your own routines as needed)
; 
;               *=    $1000             ; locate program beginning at $1000


.code

.export test_ps2_keyboard
test_ps2_keyboard:
               jsr   KBINIT            ; init the keyboard, LEDs, and flags
lp0:            jsr   acia_put_newline          ; prints 0D 0A (CR LF) to the terminal
lp1:            jsr   KBINPUT           ; wait for a keypress, return decoded ASCII code in A
               cmp   #SC_SPECIAL
               beq   lp1
               cmp   #$0d              ; if CR, then print CR LF to terminal
               beq   lp0               ; 
               cmp   #$1B              ; esc ascii code
               beq   lp2               ; 
               cmp   #$20              ; 
               bcc   lp3               ; control key, print as <hh> except $0d (CR) & $2B (Esc)
               cmp   #$80              ; 
               bcs   lp3               ; extended key, just print the hex ascii code as <hh>
               cmp   #$00
               beq   printunkown
               jsr   acia_putc            ; prints contents of A reg to the Terminal, ascii 20-7F
               bra   lp1               ; 
lp2:            rts                     ; done
lp3:            pha                     ; 
               lda   #$3C              ; <
               jsr   acia_putc         ; 
               pla                     ; 
               jsr   print1byte        ; print 1 byte in ascii hex
               lda   #$3E              ; >
               jsr   acia_putc         ; 
               bra   lp1               ; 

print1byte:
            pha
            ld16 R0,sbuf
            pla
            jsr fmt_hex_string
            jsr acia_puts
            rts
print_binary:
            pha
            ld16 R0,sbuf
            pla
            jsr fmt_bin_string
            jsr acia_puts
            rts
printunkown:
            pha
            lda #'['
            jsr acia_putc
            ld16 R0,sbuf
            lda byte
            jsr fmt_hex_string
            jsr acia_puts
            lda #']'
            jsr acia_putc
            rts

.ifdef PS2K
;**************************************************************************************
;
; special read routine for my games - returns key code pressed in KBD_CHAR and KBD_SPECIAL
; if C=0 then scan didn't read anything, so nothing is waiting. Set KBD_CHAR=0 and return immediately.
; if KBD_CHAR == FF then it is a break code and code is in KBD_SPECIAL
;
KBSCAN_GAME:
ksg_loop:
    phx
    jsr KBSCAN            ; scan once
    bcs ksg_key_ready
    stz KBD_CHAR
    plx
    clc
    rts

ksg_key_ready:
ksg_scrl_off:
    ; Turn off scroll lock
    jsr kbtscrl           ; turn off scroll lock (ready to input)  
    bne ksg_scrl_off     ; ensure its off 

ksg_get_code:
    ; Get a code and check for special cases, looping back if this is not a make/break code
    jsr KBGET
    jsr kbcsrch           ; scan for 14 codes  (also sets break-sequence indicator)
    ;beq ksg_get_code     ; 0 = get more codes

    sta KBD_CHAR

    plx
    sec
    rts

;**************************************************************************************
;
; Decoding routines
;
; KBINPUT is the main routine to call to get an ascii char from the keyboard
; (waits for a non-zero ascii code)
;
; returns KBD_CHAR, KBD_SPECIAL
;   KBD_CHAR == 0       : Do Nothing (result various acks, shift keys etc)  
;   KBD_CHAR == FF      : Key Release, ASCII is in KBD_SPECIAL
;   otherwise
;   KBD_CHAR is ASCII code of key pressed

;               *=    $7000             ; place decoder @ $7000
;

kbreinit:       jsr   kbinit            ; 
kbinput:
KBINPUT:        jsr   kbtscrl           ; turn off scroll lock (ready to input)  
               bne   kbinput           ; ensure its off 
kbinput1:       jsr   kbget             ; get a code (wait for a key to be pressed)
               jsr   kbcsrch           ; scan for 14 special case codes
kbcnvt:         beq   kbinput1          ; 0=complete, get next scancode
               
               cmp   #SC_SPECIAL
               beq   kb_exit_input

               tax                     ; set up scancode as table pointer
               cmp   #$78              ; see if its the F11
               beq   kbcnvt1           ; it is, skip keypad test
               cmp   #$69              ; test for keypad codes 69
               bmi   kbcnvt1           ; thru
               cmp   #$7E              ; 7D (except 78 tested above)
               bpl   kbcnvt1           ; skip if not a keypad code
               lda   special           ; test numlock
               bit   #$02              ; numlock on?
               beq   kbcnvt2           ; no, set shifted table for special keys
               txa                     ; yes, set unshifted table for number keys
               and   #$7F              ; 
               tax                     ; 
               bra   kbcnvt3           ; skip shift test
kbcnvt1:        lda   special           ; 
               bit   #$10              ; shift enabled?
               beq   kbcnvt3           ; no
kbcnvt2:        txa                     ; yes
               ora   #$80              ; set shifted table
               tax                     ; 
kbcnvt3:        lda   special           ;
               bit   #$08              ; control?
               beq   kbcnvt4           ; no
               lda   ASCIITBL,x        ; get ascii code
               cmp   #$8F              ; {ctrl-Printscrn - do re-init or user can remove this code }
               beq   kbreinit          ; {do kb reinit                                             }
               and   #$1F              ; mask control code (assumes A-Z is pressed)
               beq   kbinput1          ; ensure mask didn't leave 0
               tax                     ; 
               bra   kbdone            ; 
kbcnvt4:        lda   ASCIITBL,x        ; get ascii code
               beq   kbinput1          ; if ascii code is 0, invalid scancode, get another
               tax                     ; save ascii code in x reg
               lda   special           ; 
               bit   #$04              ; test caps lock
               beq   kbdone            ; caps lock off
               txa                     ; caps lock on - get ascii code
               cmp   #$61              ; test for lower case a
               bcc   kbdone            ; if less than, skip down
               cmp   #$7B              ; test for lower case z
               bcs   kbdone            ; if greater than, skip down
               sec                     ; alpha chr found, make it uppercase
               sbc   #$20              ; if caps on and lowercase, change to upper
               tax                     ; put new ascii to x reg
kbdone:         phx                     ; save ascii to stack
kbdone1:        jsr   kbtscrl           ; turn on scroll lock (not ready to receive)
               beq   kbdone1           ; ensure scroll lock is on
               pla                     ; get ASCII code
               ;AND #$7F
; debug - print decoded ASCII
;sta KBD_CHAR
;lda #'<'
;jsr acia_putc
;lda KBD_CHAR
;jsr print1byte
;lda #'>'
;jsr acia_putc
;jsr acia_put_newline
;lda KBD_CHAR
; end debug

kb_exit_input:
               STA KBD_CHAR
               sec
               rts                     ; return to calling program
;
;******************************************************************************
;
; scan code processing routines
;
;
kbtrap83:       lda   #$02              ; traps the F7 code of $83 and chang
               rts                     ; 
;
kbsshift:       lda   #$10              ; *** neat trick to tuck code inside harmless cmd
               .byte $2c               ; *** use BIT Absolute to skip lda #$02 below
kbsctrl:        lda   #$08              ; *** disassembles as  LDA #$01
               ora   special           ;                      BIT $A902
               sta   special           ;                      ORA $02D3
               bra   kbnull            ; return with 0 in A
;
kbtnum:         lda   special           ; toggle numlock bit in special
               eor   #$02              ; 
               sta   special           ; 
               jsr   kbsled            ; update keyboard leds
               bra   kbnull            ; return with 0 in A
;
kbresend:       lda   lastbyte          ; 
               jsr   kbsend            ; 
               bra   kbnull            ; return with 0 in A
;
kbtcaps:        lda   special           ; toggle caps bit in special
               eor   #$04              ; 
               sta   special           ; 
               jsr   kbsled            ; set new status leds
kbnull:         lda   #$00              ; set caps, get next code
               rts                     ; 

kbrls_return:   sta   KBD_SPECIAL       ; set break key code
               lda   #SC_SPECIAL
               rts

; Extended key encountered : so far had E0
;
kbExt:          jsr   kbget             ; get next code
               cmp   #$F0              ; is it an extended key release?
               beq   kbexrls           ; test for shift, ctrl, caps
               ;jsr   ps2k_debug_print_extcode
               cmp   #$14              ; right control?
               beq   kbsctrl           ; set control and get next scancode
               ldx   #$09              ; test for 8 scancode to be relocated
kbext1:         cmp   kbextlst,x        ; scan list
               beq   kbext3            ; get data if match found
               dex                     ; get next item
               bpl   kbext1            ; 
               cmp   #$3F              ; not in list, test range 00-3f or 40-7f
               bmi   kbExt2            ; its a windows/alt key, just return unshifted
               ora   #$80              ; return scancode and point to shifted table
kbExt2:         rts                     ; 
kbext3:         lda   kbextdat,x        ; get new scancode
               rts                     ; 
;
kbextlst:       .byte $7E               ; E07E ctrl-break scancode
               .byte $4A               ; E04A kp/
               .byte $12               ; E012 scancode
               .byte $7C               ; E07C prt scrn 
               .byte $6B               ; E06B Left arrow
               .byte $72               ; E072 Down arrow
               .byte $74               ; E074 Right arrow
               .byte $75               ; E075 Up arrow
               .byte $71               ; E071 Delete
;
kbextdat:      .byte $20               ; new ctrl-brk scancode   
               .byte $6A               ; new kp/ scancode     
               .byte $00               ; do nothing (return and get next scancode)
               .byte $0F               ; new prt scrn scancode
               .byte $62               ; new Left arrow scancode    - map to ASCII $B0
               .byte $63               ; new Down arrow scancode    - map to ASCII $B1
               .byte $64               ; new Right arrow scancode   - map to ASCII $B2
               .byte $65               ; new Up arrow scancode  - map to ASCII $B3
               .byte $67               ; E071 Delete - then map to ASCII $B4
;
kbexrls:
               jsr   kbget             ; 
               cmp   #$12              ; is it a release of the E012 code?
               bne   kbrlse1           ; no - process normal release
               bra   kbnull            ; return with 0 in A
;
; key release: so far encountered an F0
; get the next byte and test for shift
kbrlse:        jsr   kbget             ; test for shift & ctrl
               cmp   #$12              ;  (left shift)
               beq   kbrshift          ; reset shift bit 
               cmp   #$59              ;  (right shift)
               beq   kbrshift          ; 

;
; process key released (called by both normal and extended key release)
kbrlse1:        
               cmp   #$14              ; test for ctrl
               beq   kbrctrl           ; 
               cmp   #$11              ; alt key release
               ;bne   kbnull           ; return with 0 in A
               bne   kbrls_return      ; return with SC_SPECIAL($FF) in A and key code in KBD_SPECIAL
kbralt:        lda   #$13              ; new alt release scancode
               rts                     ; 

kbrctrl:       lda   #$F7              ; reset ctrl bit in special
               .byte $2c               ; use (BIT Absolute) to skip lda #$EF if passing down
kbrshift:      lda   #$EF              ; reset shift bit in special
               and   special           ; 
               sta   special           ; 
               bra   kbnull            ; return with 0 in A

kbtscrl:        lda   special           ; toggle scroll lock bit in special
               eor   #$01              ; 
               sta   special           ; 
               jsr   kbsled            ; update keyboard leds
               lda   special           ; 
               bit   #$01              ; check scroll lock status bit
               rts                     ; return
;
kbBrk:          ldx   #$07              ; ignore next 7 scancodes then
kbBrk1:         jsr   kbget             ; get scancode
               dex                     ; 
               bne   kbBrk1            ; 
               lda   #$10              ; new scan code
               rts                     ; 
;
kbcsrch:        ldx   #$0E              ; 14 codes to check
kbcsrch1:       cmp   kbclst,x          ; search scancode table for special processing
               beq   kbcsrch2          ; if found run the routine
               dex                     ; 
               bpl   kbcsrch1          ; 
               rts                     ; no match, return from here for further processing
kbcsrch2:       txa                     ; code found - get index
               asl                     ; mult by two
               tax                     ; save back to x
               lda   byte              ; load scancode back into A 
               jmp   (kbccmd,x)        ; execute scancode routine, return 0 if done
                                       ; nonzero scancode if ready for ascii conversion
;
;keyboard command/scancode test list
; db=define byte, stores one byte of data
;
kbclst:         .byte $83               ; F7 - move to scancode 02
               .byte $58               ; caps
               .byte $12               ; Lshift
               .byte $59               ; Rshift
               .byte $14               ; ctrl
               .byte $77               ; num lock
               .byte $E1               ; Extended pause break 
               .byte $E0               ; Extended key handler
               .byte $F0               ; Release 1 byte key code
               .byte KB_ACK            ; Ack 
               .byte $AA               ; POST passed
               .byte $EE               ; Echo
               .byte $FE               ; resend
               .byte $FF               ; overflow/error
               .byte $00               ; underflow/error
;
; command/scancode jump table
; 
kbccmd:         .word kbtrap83          ; 
               .word kbtcaps           ; 
               .word kbsshift          ; 
               .word kbsshift          ; 
               .word kbsctrl           ; 
               .word kbtnum            ; 
               .word kbBrk             ; 
               .word kbExt             ; 
               .word kbrlse            ; 
               .word kbnull            ; 
               .word kbnull            ; 
               .word kbnull            ; 
               .word kbresend          ; 
               .word kbflush           ; 
               .word kbflush           ; 
;
;**************************************************************
;
; Keyboard I/O suport
;

;
; KBSCAN will scan the keyboard for incoming data for about
; 105uS and returns with A=0 if no data was received.
; It does not decode anything, the non-zero value in A if data
; is ready is ambiguous.  You must call KBGET or KBINPUT to
; get the keyboard data.
;
KBSCAN:         
               phx                  ;4
               ldx   #$12           ;2 ; timer: x = (cycles - 40)/13   (105-40)/13=5
                                       ; @2.45MHz cycles=217 loop=12 (257-40)/12=18
               lda   kbportddr      ;4 ; 
               and   #$CF           ;2 ; set clk to input (change if port bits change)
               sta   kbportddr      ;4 ; 
kbscan1:        lda   #clk           ;2 ; 
               bit   kbportreg      ;4 ; 
               beq   kbscan2        ;2 ; if clk goes low, data ready
               dex                  ;2 ; reduce timer
               bne   kbscan1        ;2 ; wait while clk is high
               jsr   kbdis             ; timed out, no data, disable receiver
               plx
               lda   #$00              ; set data not ready flag
               clc                     ; data not ready - C=0
               rts                     ; return 

kbscan2:        jsr   kbdis             ; disable the receiver so other routines get it
; Three alternative exits if data is ready to be received: Either return or jmp to handler
               plx
               sec                      ; data ready - C=1
               rts                     ; return (A<>0, A=clk bit mask value from kbdis)
;               jsr   KBINPUT           ; if key pressed, decode it with KBINPUT
;               sec                      ; data ready - C=1
;               rts
;               jmp   KBGET             ; if key pressed, decode it with KBGET
; ---------------------------------------------------------------------
KBINIT:          JMP kbinit

kbflush:        lda   #$f4              ; flush buffer
;
; send a byte to the keyboard
;
kbsend:         sta   byte              ; save byte to send
               phx                     ; save registers
               phy                     ; 
               sta   lastbyte          ; keep just in case the send fails
;debug - print send code
;ld16 R0,msg_send
;jsr acia_puts
;lda #'['
;jsr acia_putc
;lda byte
;jsr print1byte
;lda #']'
;jsr acia_putc
;jsr acia_put_newline
; end debug
               lda   kbportreg         ; 
               and   #$EF             ; clk low, data high (change if port bits change)
               ora   #data             ; 
               sta   kbportreg         ; 
               lda   kbportddr         ; 
               ora   #$30              ;  bit bits high (change if port bits change)
               sta   kbportddr         ; set outputs, clk=0, data=1
               ;lda   #$10              ; 1Mhz cpu clock delay (delay = cpuclk/62500)
               lda   #$28              ; 2.4576Mhz cpu clock delay (delay = cpuclk/62500)(Assif)
kbsendw:        dec                     ; 
               bne   kbsendw           ; 64uS delay
               ldy   #$00              ; parity counter
               ldx   #$08              ; bit counter 
               lda   kbportreg         ; 
               and   #$CF              ; clk low, data low (change if port bits change)
               sta   kbportreg         ; 
               lda   kbportddr         ; 
               and   #$EF              ; set clk as input (change if port bits change)
               sta   kbportddr         ; set outputs
               jsr   kbhighlow         ; 
kbsend1:        ror   byte              ; get lsb first
               bcs   kbmark            ; 
               lda   kbportreg         ; 
               and   #$DF              ; turn off data bit (change if port bits change)
               sta   kbportreg         ; 
               bra   kbnext            ; 
kbmark:         lda   kbportreg         ; 
               ora   #data             ; 
               sta   kbportreg         ; 
               iny                     ; inc parity counter
kbnext:         jsr   kbhighlow         ; 
               dex                     ; 
               bne   kbsend1           ; send 8 data bits
               tya                     ; get parity count
               and   #$01              ; get odd or even
               bne   kbpclr            ; if odd, send 0
               lda   kbportreg         ; 
               ora   #data             ; if even, send 1
               sta   kbportreg         ; 
               bra   kback             ; 
kbpclr:         lda   kbportreg         ; 
               and   #$DF              ; send data=0 (change if port bits change)
               sta   kbportreg         ; 
kback:          jsr   kbhighlow         ; 
               lda   kbportddr         ; 
               and   #$CF              ; set clk & data to input (change if port bits change)
               sta   kbportddr         ; 
               ply                     ; restore saved registers
               plx                     ; 
               jsr   kbhighlow         ; wait for ack from keyboard
               bne   kbinit_redirect   ; VERY RUDE error handler - re-init the keyboard
kbsend2:        lda   kbportreg         ; 
               and   #clk              ; 
               beq   kbsend2           ; wait while clk low
               jmp   kbdis             ; diable kb sending
kbinit_redirect:
    jmp kbinit
;
; KBGET waits for one scancode from the keyboard
;
kberror:        
; debug
ld16 R0,msg_error
jsr acia_puts
; enddebug
               lda   #KBCMD_RESEND     ; resend cmd
               jsr   kbsend            ; 
kbget:
KBGET:          phx                     ; 
               phy                     ; 
               lda   #$00              ; 
               sta   byte              ; clear scankey holder
               sta   parity            ; clear parity holder
               ldy   #$00              ; clear parity counter
               ldx   #$08              ; bit counter 
               lda   kbportddr         ; 
               and   #$CF              ; set clk to input (change if port bits change)
               sta   kbportddr         ; 
kbget1:         lda   #clk              ; 
               bit   kbportreg         ; 
               bne   kbget1            ; wait while clk is high
               lda   kbportreg         ; 
               and   #data             ; get start bit 
               bne   kbget1            ; if 1, false start bit, do again 
kbget2:         jsr   kbhighlow         ; wait for clk to return high then go low again
               cmp   #$01              ; set c if data bit=1, clr if data bit=0
                                       ; (change if port bits change) ok unless data=01 or 80
                                       ; in that case, use ASL or LSR to set carry bit
               ror   byte              ; save bit to byte holder
               bpl   kbget3            ; 
               iny                     ; add 1 to parity counter
kbget3:         dex                     ; dec bit counter
               bne   kbget2            ; get next bit if bit count > 0 
               jsr   kbhighlow         ; wait for parity bit
               beq   kbget4            ; if parity bit 0 do nothing
               inc   parity            ; if 1, set parity to 1        
kbget4:         tya                     ; get parity count
               ply                     ; 
               plx                     ; 
               eor   parity            ; compare with parity bit
               and   #$01              ; mask bit 1 only
               beq   kberror           ; bad parity
               jsr   kbhighlow         ; wait for stop bit
               beq   kberror           ; 0=bad stop bit 
               lda   byte              ; if byte & parity 0,  
               beq   kbget             ; no data, do again
               jsr   kbdis             ; 
               lda   byte              ; 
;cmp #$FA
;beq noprint
;jsr ps2k_debug_print_scan_code
;lda byte
;noprint:
               rts                     ; 

;
kbdis:          lda   kbportreg         ; disable kb from sending more data
               and   #$EF              ; clk = 0 (change if port bits change)
               sta   kbportreg         ; 
               lda   kbportddr         ; set clk to ouput low
               and   #$CF              ; (stop more data until ready) (change if port bits change)
               ora   #clk              ; 
               sta   kbportddr         ; 
               rts                     ; 
kbinit:
               lda   #$02              ; init - num lock on, all other off
               sta   special           ; 
kbinit1:        lda   #KBCMD_RESET      ; keybrd reset
               jsr   kbsend            ; reset keyboard
               jsr   kbget             ; 
               cmp   #KB_ACK           ; ack?
               bne   kbinit1           ; resend reset cmd
               jsr   kbget             ; 
               cmp   #$AA              ; reset ok
               bne   kbinit1           ; resend reset cmd        
                                       ; fall into to set the leds
  ; debug
               ld16  R0,msg_init
               jsr   acia_puts

kbsled:         lda   #KBCMD_LEDS       ; Set the keybrd LED's from kbleds variable
               jsr   kbsend            ; 
               jsr   kbget             ; 
               cmp   #KB_ACK              ; ack?
               bne   kbsled            ; resend led cmd        
               lda   special           ; 
               and   #$07              ; ensure bits 3-7 are 0
               jsr   kbsend            ; 
               jsr   kbget             ; get the ack
               rts                     ; 
                                       ; 
kbhighlow:      lda   #clk              ; wait for a low to high to low transition
               bit   kbportreg         ; 
               beq   kbhighlow         ; wait while clk low
kbhl1:          bit   kbportreg         ; 
               bne   kbhl1             ; wait while clk is high
               lda   kbportreg         ; 
               and   #data             ; get data line state
               rts                     ; 

; Turn off typematic (repeat)
KBTMOFF:
        ld16 R0,msg_tm_off
        jsr acia_puts
        lda #KBCMD_SETALLMB     ; set all keys to make/break
        jsr kbsend              ; send command to keyboard
        jsr kbget               ; expect an ACK
        jsr ps2k_debug_print_scan_code
        cmp #KB_ACK             ;
        bne KBTMOFF             ; just resend command if not ACK
        rts
; Turn on typematic (repeat)
KBTMON:
        ld16 R0,msg_tm_on
        jsr acia_puts
        lda #KBCMD_SETALLTMB    ; set all keys to make/break/typematic
        jsr kbsend              ;
        jsr kbget               ; 
        cmp #KB_ACK             ;
        bne KBTMON              ;
        rts

; Scan codes are also in io.s65
;*************************************************************
;
; Unshifted table for scancodes to ascii conversion
;                                      Scan|Keyboard
;                                      Code|Key
;                                      ----|----------
ASCIITBL:       .byte $00               ; 00 no key pressed
               .byte $89               ; 01 F9
               .byte $87               ; 02 relocated F7
               .byte $85               ; 03 F5
               .byte $83               ; 04 F3
               .byte $81               ; 05 F1
               .byte $82               ; 06 F2
               .byte $8C               ; 07 F12
               .byte $00               ; 08 
               .byte $8A               ; 09 F10
               .byte $88               ; 0A F8
               .byte $86               ; 0B F6
               .byte $84               ; 0C F4
               .byte $09               ; 0D tab
               .byte $60               ; 0E `~
               .byte $8F               ; 0F relocated Print Screen key
               .byte $03               ; 10 relocated Pause/Break key
               .byte $A0               ; 11 left alt (right alt too)
               .byte $00               ; 12 left shift
               .byte $E0               ; 13 relocated Alt release code
               .byte $00               ; 14 left ctrl (right ctrl too)
               .byte $71               ; 15 qQ
               .byte $31               ; 16 1!
               .byte $5B               ; 17 
               .byte $00               ; 18 
               .byte $00               ; 19 
               .byte $7A               ; 1A zZ
               .byte $73               ; 1B sS
               .byte $61               ; 1C aA
               .byte $77               ; 1D wW
               .byte $32               ; 1E 2@
               .byte $A1               ; 1F Windows 98 menu key (left side)
               .byte $02               ; 20 relocated ctrl-break key
               .byte $63               ; 21 cC
               .byte $78               ; 22 xX
               .byte $64               ; 23 dD
               .byte $65               ; 24 eE
               .byte $34               ; 25 4$
               .byte $33               ; 26 3#
               .byte $A2               ; 27 Windows 98 menu key (right side)
               .byte $00               ; 28
               .byte $20               ; 29 space
               .byte $76               ; 2A vV
               .byte $66               ; 2B fF
               .byte $74               ; 2C tT
               .byte $72               ; 2D rR
               .byte $35               ; 2E 5%
               .byte $A3               ; 2F Windows 98 option key (right click, right side)
               .byte $00               ; 30
               .byte $6E               ; 31 nN
               .byte $62               ; 32 bB
               .byte $68               ; 33 hH
               .byte $67               ; 34 gG
               .byte $79               ; 35 yY
               .byte $36               ; 36 6^
               .byte $00               ; 37
               .byte $00               ; 38
               .byte $00               ; 39
               .byte $6D               ; 3A mM
               .byte $6A               ; 3B jJ
               .byte $75               ; 3C uU
               .byte $37               ; 3D 7&
               .byte $38               ; 3E 8*
               .byte $00               ; 3F
               .byte $00               ; 40
               .byte $2C               ; 41 ,<
               .byte $6B               ; 42 kK
               .byte $69               ; 43 iI
               .byte $6F               ; 44 oO
               .byte $30               ; 45 0)
               .byte $39               ; 46 9(
               .byte $00               ; 47
               .byte $00               ; 48
               .byte $2E               ; 49 .>
               .byte $2F               ; 4A /?
               .byte $6C               ; 4B lL
               .byte $3B               ; 4C ;:
               .byte $70               ; 4D pP
               .byte $2D               ; 4E -_
               .byte $00               ; 4F
               .byte $00               ; 50
               .byte $00               ; 51
               .byte $27               ; 52 '"
               .byte $00               ; 53
               .byte $5B               ; 54 [{
               .byte $3D               ; 55 =+
               .byte $5B               ; 56  new \|
               .byte $00               ; 57
               .byte $00               ; 58 caps
               .byte $00               ; 59 r shift
               .byte $0D               ; 5A <Enter>
               .byte $5D               ; 5B ]}
               .byte $00               ; 5C
               .byte $23               ; 5D \| (now #~)
               .byte $00               ; 5E
               .byte $00               ; 5F
               .byte $00               ; 60
               .byte $5B               ; 61 (new \|)
               .byte $B0               ; 62 (new Left Arrow)
               .byte $B1               ; 63 (new Down Arrow)
               .byte $B2               ; 64 (new Right Arrow)
               .byte $B3               ; 65 (new Up Arrow)
               .byte $08               ; 66 bkspace
               .byte $B4               ; 67 Delete (relocated)
               .byte $00               ; 68
               .byte $31               ; 69 kp 1
               .byte $2f               ; 6A kp / converted from E04A in code
               .byte $34               ; 6B kp 4
               .byte $37               ; 6C kp 7
               .byte $00               ; 6D
               .byte $00               ; 6E
               .byte $00               ; 6F
               .byte $30               ; 70 kp 0
               .byte $2E               ; 71 kp .
               .byte $32               ; 72 kp 2
               .byte $35               ; 73 kp 5
               .byte $36               ; 74 kp 6
               .byte $38               ; 75 kp 8
               .byte $1B               ; 76 esc
               .byte $00               ; 77 num lock
               .byte $8B               ; 78 F11
               .byte $2B               ; 79 kp +
               .byte $33               ; 7A kp 3
               .byte $2D               ; 7B kp -
               .byte $2A               ; 7C kp *
               .byte $39               ; 7D kp 9
               .byte $8D               ; 7E scroll lock
               .byte $00               ; 7F 
;
; Table for shifted scancodes 
;        
               .byte $00               ; 80 
               .byte $C9               ; 81 F9
               .byte $C7               ; 82 relocated F7 
               .byte $C5               ; 83 F5 (F7 actual scancode=83)
               .byte $C3               ; 84 F3
               .byte $C1               ; 85 F1
               .byte $C2               ; 86 F2
               .byte $CC               ; 87 F12
               .byte $00               ; 88 
               .byte $CA               ; 89 F10
               .byte $C8               ; 8A F8
               .byte $C6               ; 8B F6
               .byte $C4               ; 8C F4
               .byte $09               ; 8D tab
               .byte $7E               ; 8E `~
               .byte $CF               ; 8F relocated Print Screen key
               .byte $03               ; 90 relocated Pause/Break key
               .byte $A0               ; 91 left alt (right alt)
               .byte $00               ; 92 left shift
               .byte $E0               ; 93 relocated Alt release code
               .byte $00               ; 94 left ctrl (and right ctrl)
               .byte $51               ; 95 qQ
               .byte $21               ; 96 1!
               .byte $7C               ; 97 
               .byte $00               ; 98 
               .byte $00               ; 99 
               .byte $5A               ; 9A zZ
               .byte $53               ; 9B sS
               .byte $41               ; 9C aA
               .byte $57               ; 9D wW
               .byte $22               ; 9E 2@
               .byte $E1               ; 9F Windows 98 menu key (left side)
               .byte $02               ; A0 relocated ctrl-break key
               .byte $43               ; A1 cC
               .byte $58               ; A2 xX
               .byte $44               ; A3 dD
               .byte $45               ; A4 eE
               .byte $24               ; A5 4$
               .byte $7F               ; A6 3#
               .byte $E2               ; A7 Windows 98 menu key (right side)
               .byte $00               ; A8
               .byte $20               ; A9 space
               .byte $56               ; AA vV
               .byte $46               ; AB fF
               .byte $54               ; AC tT
               .byte $52               ; AD rR
               .byte $25               ; AE 5%
               .byte $E3               ; AF Windows 98 option key (right click, right side)
               .byte $00               ; B0
               .byte $4E               ; B1 nN
               .byte $42               ; B2 bB
               .byte $48               ; B3 hH
               .byte $47               ; B4 gG
               .byte $59               ; B5 yY
               .byte $5E               ; B6 6^
               .byte $00               ; B7
               .byte $00               ; B8
               .byte $00               ; B9
               .byte $4D               ; BA mM
               .byte $4A               ; BB jJ
               .byte $55               ; BC uU
               .byte $26               ; BD 7&
               .byte $2A               ; BE 8*
               .byte $00               ; BF
               .byte $00               ; C0
               .byte $3C               ; C1 ,<
               .byte $4B               ; C2 kK
               .byte $49               ; C3 iI
               .byte $4F               ; C4 oO
               .byte $29               ; C5 0)
               .byte $28               ; C6 9(
               .byte $00               ; C7
               .byte $00               ; C8
               .byte $3E               ; C9 .>
               .byte $3F               ; CA /?
               .byte $4C               ; CB lL
               .byte $3A               ; CC ;:
               .byte $50               ; CD pP
               .byte $5F               ; CE -_
               .byte $00               ; CF
               .byte $00               ; D0
               .byte $00               ; D1
               .byte $40               ; D2 '"
               .byte $00               ; D3
               .byte $7B               ; D4 [{
               .byte $2B               ; D5 =+
               .byte $7C               ; D6 new \|
               .byte $00               ; D7
               .byte $00               ; D8 caps
               .byte $00               ; D9 r shift
               .byte $0D               ; DA <Enter>
               .byte $7D               ; DB ]}
               .byte $00               ; DC
               .byte $7E               ; DD \|
               .byte $00               ; DE
               .byte $00               ; DF
               .byte $00               ; E0
               .byte $7C               ; E1 (new \|)
               .byte $B0               ; E2 (new Left Arrow)
               .byte $B1               ; E3 (new Down Arrow)
               .byte $B2               ; E4 (new Right Arrow)
               .byte $B3               ; E5 (new Up Arrow)
               .byte $08               ; E6 bkspace
               .byte $B4               ; E7 Delete (relocated)
               .byte $00               ; E8
               .byte $91               ; E9 kp 1
               .byte $2f               ; EA kp / converted from E04A in code
               .byte $94               ; EB kp 4
               .byte $97               ; EC kp 7
               .byte $00               ; ED
               .byte $00               ; EE
               .byte $00               ; EF
               .byte $90               ; F0 kp 0
               .byte $71               ; F1 kp .
               .byte $92               ; F2 kp 2
               .byte $95               ; F3 kp 5
               .byte $96               ; F4 kp 6
               .byte $98               ; F5 kp 8
               .byte $1B               ; F6 esc
               .byte $00               ; F7 num lock
               .byte $CB               ; F8 F11
               .byte $2B               ; F9 kp +
               .byte $93               ; FA kp 3
               .byte $2D               ; FB kp -
               .byte $2A               ; FC kp *
               .byte $99               ; FD kp 9
               .byte $CD               ; FE scroll lock
; NOT USED     .byte $00               ; FF 
; end
.endif

msg_scan_code:
    .byte "Scan:",$00
msg_error:
    .byte "Error",$0D,$0A,$00
msg_send:
    .byte "-->",$00
msg_init:
    .byte "PS2 Keyboard Initialised",$0D,$0A,$00
msg_tm_off:
    .byte "Set TM Off",$0D,$0A,$00
msg_tm_on:
    .byte "Set TM On",$0D,$0A,$00

ps2k_debug_print_scan_code:
    pha
    ld16 R0,msg_scan_code
    jsr acia_puts
    pla
    pha
    jsr print1byte
    ;lda #' '
    ;jsr acia_putc
    ;pla
    ;pha
    ;jsr print_binary
    jsr acia_put_newline
    pla
    rts

ps2k_debug_print_extcode:
    pha
    lda #'['
    jsr acia_putc
    lda #'E'
    jsr acia_putc
    lda #'0'
    jsr acia_putc
    ld16 R0,sbuf
    pla
    pha
    jsr fmt_hex_string
    jsr acia_puts
    lda #']'
    jsr acia_putc
    pla
    rts

.ifdef VKEYB
PCVKB_IO = $7FA0
; KBSCAN  - Scan the keyboard for 105uS, returns 0 in A if no key pressed.
;           Return ambiguous data in A if key is pressed.  Use KBINPUT OR KBGET
;           to get the key information.  You can modify the code to automatically 
;           jump to either routine if your application needs it.          
KBSCAN:
    LDA PCVKB_IO
    BEQ @None
    SEC
    RTS
@None:
    CLC
    RTS

; KBINPUT - wait for a key press and return with its assigned ASCII code in A.
KBINPUT:    
    LDA PCVKB_IO
    BEQ KBINPUT     ; one function is for KBINPUT to WAIT for a key
    CMP #$FF        ; got a key, check if it is Released
    BEQ kbi_done    ; if so ignore
    LDA PCVKB_IO    ; get ASCII
kbi_done:
    STA KBD_CHAR
    STZ PCVKB_IO    ; Ready for next key
    RTS
; KBINIT  - Initialize the keyboard and associated variables and set the LEDs
KBINIT:  ; nothing in virtual keyboard
KBTMOFF:
KBTMON:
    RTS
; KBGET   - wait for a key press and return with its unprocessed scancode in A.
KBGET:
    LDA PCVKB_IO
    BEQ KBGET           ; one function is for KBGET to WAIT for a key
    CMP #$FF            ; Check if it is Released
    BEQ kbg_releasekey
    LDA PCVKB_IO+2      ; Scan code
    STA KBD_CHAR
    STZ KBD_SPECIAL
    BRA kbg_done

kbg_releasekey:
    STA KBD_CHAR
    LDA PCVKB_IO+2      ; Scan code
    STA KBD_SPECIAL

kbg_done:
    STZ PCVKB_IO
    STZ PCVKB_IO+1
    STZ PCVKB_IO+2
    RTS
;**************************************************************************************
;
; special read routine for my games - returns key code pressed in KBD_CHAR and KBD_SPECIAL
; if C=0 then scan didn't read anything, so nothing is waiting. Set KBD_CHAR=0 and return immediately.
; if KBD_CHAR == FF then it is a break code and code is in KBD_SPECIAL
;
KBSCAN_GAME:
ksg_loop:
    phx
    jsr KBSCAN            ; scan once
    bcs ksg_key_ready
    stz KBD_CHAR
    plx
    clc
    rts

ksg_key_ready:

ksg_get_code:
    ; Get a code
    jsr KBGET
    plx
    sec
    rts
.endif

;--------------------------------------------------------------
; tests non-typematic - outputs flags for asdfghjk (8 keys)
;    KBD_CHAR_LAST ($ED) if this is not 0 print Scan code debug
; q to quit
.export test_ps2_keyboard_2
test_ps2_keyboard_2:
    jsr KBINIT
    jsr KBTMOFF
    lda #0
    sta KBD_FLAGS
    
tpk2_loop:
    jsr KBSCAN_GAME
    bcc tpk2_loop           ; carry-clear means no key

    ldx #0
    lda KBD_CHAR
    cmp #SC_SPECIAL       ; check for a break code
    bne tpk2_debug_print

    ; if result is SC_SPECIAL then this is a break code and code is in KBD_SPECIAL
    ; swap it to A and set X=1
    lda KBD_SPECIAL
    beq tpk2_loop         ; 0 in KBD_SPECIAL means it was a special key release code - ignore
    ldx #1

tpk2_debug_print:
    ; Scan code printing if debug ($ED) is turned on
    pha
    lda KBD_CHAR_LAST
    beq @over1                      ; flag is 0 so skip debug
    pla
    jsr ps2k_debug_print_scan_code  ; print scan code
    jmp @over2
@over1:
    pla
@over2:

tpk2_check_keys:
    ; check all our required keys (asdfghjk and q)
    cmp #SC_Q
    beq tpk2_done
    cmp #SC_A
    beq tpk2_do_A
    cmp #SC_S
    beq tpk2_do_S
    cmp #SC_D
    beq tpk2_do_D
    cmp #SC_F
    beq tpk2_do_F
    cmp #SC_G
    beq tpk2_do_G
    cmp #SC_H
    beq tpk2_do_H
    cmp #SC_J
    beq tpk2_do_J
    cmp #SC_K
    beq tpk2_do_K
    jmp tpk2_loop

tpk2_do_extended_JV:
    jmp tpk2_do_extended

tpk2_update:
    ; write the KBD Flags out as binary
    lda KBD_FLAGS
    jsr print_binary
    jsr acia_put_newline
    jmp tpk2_loop

tpk2_done:
    jsr KBTMON
    rts

tpk2_do_A:
    cpx #1                  ; X=1 means this is a break code
    beq @overA
    smb7 KBD_FLAGS          ; make code - set flag
    jmp tpk2_update
@overA:
    rmb7 KBD_FLAGS          ; break code - reset flag
    jmp tpk2_update

tpk2_do_S:
    cpx #1
    beq @overS
    smb6 KBD_FLAGS
    jmp tpk2_update
@overS:
    rmb6 KBD_FLAGS
    jmp tpk2_update

tpk2_do_D:
    cpx #1
    beq @overD
    smb5 KBD_FLAGS
    jmp tpk2_update
@overD:
    rmb5 KBD_FLAGS
    jmp tpk2_update

tpk2_do_F:
    cpx #1
    beq @overF
    smb4 KBD_FLAGS
    jmp tpk2_update
@overF:
    rmb4 KBD_FLAGS
    jmp tpk2_update

tpk2_do_G:
    cpx #1
    beq @overG
    smb3 KBD_FLAGS
    jmp tpk2_update
@overG:
    rmb3 KBD_FLAGS
    jmp tpk2_update

tpk2_do_H:
    cpx #1
    beq @overH
    smb2 KBD_FLAGS
    jmp tpk2_update
@overH:
    rmb2 KBD_FLAGS
    jmp tpk2_update

tpk2_do_J:
    cpx #1
    beq @overJ
    smb1 KBD_FLAGS
    jmp tpk2_update
@overJ:
    rmb1 KBD_FLAGS
    jmp tpk2_update

tpk2_do_K:
    cpx #1
    beq @overK
    smb0 KBD_FLAGS
    jmp tpk2_update
@overK:
    rmb0 KBD_FLAGS
    jmp tpk2_update

    ; deal with extended key codes and just consume the remaining codes before
    ; returning to scan loop
tpk2_do_extended:
    jsr KBGET
    cmp #$F0
    beq tpk2_ext_break_code
    jmp tpk2_loop

tpk2_ext_break_code:
    jsr KBGET
    jmp tpk2_loop

