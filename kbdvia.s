; vim ts=4
.setcpu "65C02"
.include "zeropage.inc65"
.include "io.inc65"
.include "macros.inc65"
.include "acia.inc65"
.include "string.inc65"

; TODO 
;  * repeat
;  * Run/Stop to do Ctrl-C
;  * Clr/Home to delete back to start

;---------------------------------------------------------------
;
; C64 Keyboard scan for my Homebrew 6502
; Keyboard is connected to a 6522 VIA, Port A for rows, Port B for columns
;
; somewhat based on http://codebase64.org/doku.php?id=base:reading_the_keyboard
; but also a bunch of other internet pages and my own disection of my C64 keyboard
;
; Returns :
;   Carry Set if any key has been pressed at all
;   ASCII key code in Accumulator, preserve X,Y (So I can call in the middle of the ACIA routine)
;   ZP vars KBD_SPECIAL and KBD_FLAGS for all the modifier and non-alpha keys
;   But, for RETURN and INST/DEL I'll return the ASCII codes 13d and 08d
;   (See row-col to ASCII table, KeyTable)
;
;+---------++------------------------------------------------------------------+  
;\Col VIA B \\                  Row VIA Port A (Output)                         \ 
; \ (Input ) \\  grey  \ prpl   \ blue   \green \ yello \ orng  \ red   \ brown  \ 
;  \          \\ b7 (H) \ b6 (G) \ b5 (F) \b4 (E)\ b3 (D)\ b2 (C)\ b1 (B)\ b0 (A) \
;   +----------++--------+--------+-------+-------+-------+-------+-------+--------+
;   | brwn  b0 ||INST DEL|    £   |   +   |   9   |   7   |   5   |   3   |   1    |
;   | red   b1 ||RETURN  |    *   |   P   |   I   |   Y   |   R   |   W   |  Left  |
;   | orng  b2 ||CRSR LR |    ];  |   L   |   J   |   G   |   D   |   A   |  CTRL  |
;   | yell  b3 ||CRSR UD |    ?/  |   <,  |   N   |   V   |   X   |L SHIFT|RUN STOP|
;   | grn   b4 ||  F1    |R SHIFT |   >.  |   M   |   B   |   C   |   Z   | SPACE  |
;   | blue  b5 ||  F3    |    =   |   [:  |   K   |   H   |   F   |   S   |   C=   |
;   | prpl  b6 ||  F5    |   Up   |   @   |   O   |   U   |   T   |   E   |   Q    |
;   | grey  b7 ||  F7    |CLR HOME|   -   |   0   |   8   |   6   |   4   |   2    |
;   +----------++--------+--------+-------+-------+-------+-------+-------+--------+
;   (RESTORE is wired to pins 8 and 9 and I think I will connect it to RESET - for giggles)
;
; Modifier keys (and Up/Down arrow) (Stored in KBD_FLAGS)
; +-----+-----+-----+------+------+-------+------+------+
; | b7  | b6  | b5  | b4   | b3   | b2    | b1   | b0   |
; +-----+-----+-----+------+------+-------+------+------+
; |ClrHm|UP/DN|LT/RT|R-Shft| C=   |L-Shft |RunStp|Ctrl  |
; +-----+-----+-----+------+------+-------+------+------+
; Other keys (Stored in KBD_SPECIAL)
; +----+----+----+----+-----+-----+--------+---------+
; | b7 | b6 | b5 | b4 | b3  | b2  | b1     | b0      |
; +----+----+----+----+-----+-----+--------+---------+
; | F7 | F5 | F3 | F1 | Up  |Left | RETURN | INS/DEL |
; +----+----+----+----+-----+-----+--------+---------+
;

;KBD_BUFFER_LENGTH = 10
;DBG_BUFFER_LENGTH = 10

.export kbd_init
.export kbd_scan
.export kbd_iskey
.export kbd_getkey
.export scan_buffer

; Allocate KBD Buffer in RAM (.bss)
.bss
;kbd_buffer:     .res KBD_BUFFER_LENGTH + 1, 0
;dbg_buffer:     .res DBG_BUFFER_LENGTH + 1, 0
;dbg_buffer:     .res 10,0

scan_buffer:     .res 15,0
KBD_TMP = scan_buffer+8
KBD_RPT_CNT = scan_buffer+9
KBD_DB_CNT = scan_buffer+11
KBD_CODE = scan_buffer+12

.code

; Keytable corresponding to above table - lower case
; $FF means Modifier key, $FE non-printable key
; Left arrow returns underscore (_)
; Up arrow is pipe (|)
; £ returns ascii $7F
KeyTable:
;
; R\C  7    6    5    4    3    2    1    0    R\C | 7    6    5    4    3    2    1    0    
;--------------------------------------------------+-----------------------------------------
.byte $31, $33, $35, $37, $39, $2B, $7F, $08   ; 0 | 1    3    5    7    9    +    £    Ins  
.byte $5F, $77, $72, $79, $69, $70, $2A, $0D   ; 1 | lft  w    r    y    i    p    *    Ret  
.byte $FF, $61, $64, $67, $6A, $6C, $3B, $FF   ; 2 | ctl  a    d    g    j    l    ;    c-l  
.byte $FF, $FF, $78, $76, $6E, $2C, $2F, $FF   ; 3 | stp  Lsh  x    v    n    ,    /    c-u  
.byte $20, $7A, $63, $62, $6D, $2E, $FF, $FE   ; 4 | spc  z    c    b    m    .    Rsh  F1   
.byte $FF, $73, $66, $68, $6B, $3A, $3D, $FE   ; 5 | C=   s    f    h    k    :    =    F3   
.byte $71, $65, $74, $75, $6F, $40, $7C, $FE   ; 6 | q    e    t    u    o    @    up   F5   
.byte $32, $34, $36, $38, $30, $2D, $FF, $FE   ; 7 | 2    4    6    8    0    -    clr  F7   

KeyTableShift:
;
; R\C  7    6    5    4    3    2    1    0    R\C | 7    6    5    4    3    2    1    0    
;--------------------------------------------------+-----------------------------------------
.byte $21, $23, $25, $27, $29, $2B, $7F, $08   ; 0 | !    #    %    '    )    +    £    Ins  
.byte $5F, $57, $52, $59, $49, $50, $2A, $0D   ; 1 | lft  W    R    Y    I    P    *    Ret  
.byte $FF, $41, $44, $47, $4A, $4C, $5D, $FF   ; 2 | ctl  A    D    G    J    L    ]    c-l  
.byte $03, $FF, $58, $56, $4E, $3C, $3F, $FF   ; 3 | stp  Lsh  X    V    N    <    ?    c-u  
.byte $20, $5A, $43, $42, $4D, $3E, $FF, $FE   ; 4 | spc  Z    C    B    M    >    Rsh  F1   
.byte $FF, $53, $46, $48, $4B, $5B, $3D, $FE   ; 5 | C=   S    F    H    K    [    =    F3   
.byte $51, $45, $54, $55, $4F, $40, $7C, $FE   ; 6 | Q    E    T    U    O    @    up   F5   
.byte $22, $24, $26, $28, $30, $2D, $FF, $FE   ; 7 | "    $    &    (    0    -    clr  F7   

;---------------------------------------------------------------
; Setup VIA 6552
; Port A is Rows (Output), Port B is Cols (Input)
; 
kbd_init:       LDA #$FF
				STA VIA1+VIA_DDRA		; Port A all lines output (rows)
				STA VIA1+VIA_ORA		; turn off all lines
                LDA #$00
				STA VIA1+VIA_DDRB		; Port B all lines input
				STA VIA1+VIA_PCR		; Peripheral Control Reg (interrupts & handshaking)
				STA KBD_CHAR			; Key detected
				STA KBD_CHAR_LAST		; Last key detected
				STA KBD_RPT_CNT
				STA KBD_RPT_CNT+1
                STA KBD_DB_CNT
                RTS

;---------------------------------------------------------------
; kbd_scan. Call to do a quick scan of the Keyboard to determine
;           if any keys are pressed at all
;           Write ALL 0s to B, Read A
kbd_scan:       phxy
				LDA #0					   ; 1st test all rows to see if anything is pressed
				STA VIA1+VIA_ORA           ; Write 0s to ALL rows
				LDA VIA1+VIA_IRB           ; Read columns
				BNE kbd_save_cols          ; Not 0 means: Found a key pressed

; No key pressed, return C=0, KBD_CHAR=0
no_key:         
                ; debounce
                LDA KBD_DB_CNT
                BEQ nk_resetlast            ; debounce ctr=0 so reset last to really register a key-up
                DEC KBD_DB_CNT              ; otherwise decrement last and don't register a different key
                JMP same_as_last
nk_resetlast:
                LDA #0
                STA KBD_CHAR
				STA KBD_CHAR_LAST
				STA KBD_RPT_CNT
				STA KBD_RPT_CNT+1
                plxy                       ; restore x&y 
                CLC                        ; C=0 means no key
                RTS

;---------------------------------------------------------------
; kbd-getkey: turn on rows in turn and save the results (columns)
;
kbd_save_cols:  LDX #0
                STX KBD_FLAGS
                LDA #%11111110    ; Bit7 of B corresponds to Row A above
								  ; set b0 to 0 to test row
				STA KBD_CHAR	  ; store in temp, we'll ROL it later to test each row
@save_loop:     STA VIA1+VIA_ORA       ; select a row
				LDA VIA1+VIA_IRB       ; read column
                STA scan_buffer,X ; and store for later interpretation
                SEC               ; move on
				ROL KBD_CHAR      ; to next row
                LDA KBD_CHAR
                INX
                CPX #8
                BNE @save_loop

				LDA #$FF          ; Disconnect tows
                STA VIA1+VIA_ORA
				LDA #0			  ; done with temp var
				STA KBD_CHAR
                
; Modifier keys (and Up/Down arrow) (Stored in KBD_FLAGS)
; +-----+-----+-----+------+------+-------+------+------+
; | b7  | b6  | b5  | b4   | b3   | b2    | b1   | b0   |
; +-----+-----+-----+------+------+-------+------+------+
; |ClrHm|UP/DN|LT/RT|R-Shft| C=   |L-Shft |RunStp|Ctrl  |
; +-----+-----+-----+------+------+-------+------+------+
;
; Other keys (Stored in KBD_SPECIAL)
; +----+----+----+----+-----+-----+--------+---------+
; | b7 | b6 | b5 | b4 | b3  | b2  | b1     | b0      |
; +----+----+----+----+-----+-----+--------+---------+
; | F7 | F5 | F3 | F1 |     |     | RETURN | INS/DEL |
; +----+----+----+----+-----+-----+--------+---------+
                ; Set special flags 
				LDA scan_buffer
                EOR #$ff
                AND #%00101100     ; _ _ C= _ RunS Ctrl _ _
                LSR
                LSR
                ORA KBD_FLAGS      ; if we are here a 2nd time round keep prev flags
                STA KBD_FLAGS

				LDA scan_buffer+1
                EOR #$ff
                AND #%00001000     ; _ _ _ _ LShf _ _ _
                LSR                ; 
                ORA KBD_FLAGS      
                STA KBD_FLAGS
				LDA scan_buffer+6
                EOR #$ff
                AND #%11010000     ; ClHm UArw _ RShf _ _ _ _ 
                ORA KBD_FLAGS
                STA KBD_FLAGS
				LDA scan_buffer+7
                EOR #$ff
                AND #%00001100     ; _ _ _ _ C-UpDn C-LtRt _ _
                ASL
                ASL
                ASL
                ORA KBD_FLAGS
                STA KBD_FLAGS
                
                LDA scan_buffer+7     ; Function keys, Ret, Ins
                EOR #$ff
                AND #%11110011
                ORA KBD_SPECIAL
                STA KBD_SPECIAL
                
                LDA scan_buffer+6
                EOR #$FF
                AND #%01000000        ; Up arrow
                LSR
                LSR
                LSR
                ORA KBD_SPECIAL
                STA KBD_SPECIAL
                LDA scan_buffer
                EOR #$FF
                AND #%00000010        ; Left arrow
                ORA KBD_SPECIAL
                ASL
                STA KBD_SPECIAL

; Alpha numeric keys
scan_alphanum:
                ; Check all of scan results for the Alpha key
                LDX #$FF           ; 1st time X=0
next_scan_byte: INX 
				LDA scan_buffer,X
                LDY #7
next_scan_bit:  SEC
                ROL                ; Check bit 0 of A
                BCC FOUNDKEY
get_anoth_key:  DEY             
                BPL next_scan_bit  ; Branch-on-Plus (ie.0-7 but not $FF)
                CPX #7
                BNE next_scan_byte

; Gone through all keys
				LDA KBD_CHAR
				CMP #0
				BNE all_keys_found
				JMP no_key

;---------------------------------------------------------------
; Found some key pressed.
; Return A=[Key code] Carry=1 X,Y preserved
;
FOUNDKEY:       ; X will have Row, Y Col, lookup key in table
                ; save X and Y and calculate offset into lookup table
                STA KBD_TMP
                phx
                phy
                TYA
                ASL                     ; multiply row by 8 to get index into lookup table
                ASL
                ASL
                STA TMP2
                TXA                     ; Add Col number
                ADC TMP2
                TAX                     ; store in X to give index
                
                ; check if shift is pressed
                LDA KBD_FLAGS
                AND #%00010100
                BNE capitals

                ; lowercase lookup
                LDA KeyTable,X
                STA KBD_CHAR
                JMP fk_over
                
capitals:       ; uppercase lookup
                LDA KeyTableShift,X
                STA KBD_CHAR

fk_over:        ply            ; restore X and Y so jumping back into loop works
                plx

                CMP #$FF                ; if it is a non alpha modifier, go get another key
				BNE all_keys_found
                LDA KBD_TMP
                JMP get_anoth_key       ; jump back into the loop!


;---------------------------------------------------------------
;  Return A=char C=1 X,Y preserved
all_keys_found: 
                LDA KBD_CHAR
				CMP #$FF
				BEQ found_modifier_key      
				CMP #$FE
				BEQ found_special_key      
				BRA found_real_key

found_modifier_key:
found_special_key:
                ; debounce
                LDA KBD_DB_CNT
                BEQ fk_resetlast            ; debounce ctr=0 so reset last to really register a key-up
                DEC KBD_DB_CNT              ; otherwise decrement last and don't register a different key
                JMP same_as_last

fk_resetlast:
				LDA #0
				STA KBD_CHAR_LAST
				STA KBD_RPT_CNT
				STA KBD_RPT_CNT+1
				;LDA #0
                plxy
                CLC
                RTS
found_real_key:
				LDA KBD_CHAR
				CMP KBD_CHAR_LAST
				BEQ same_as_last
				STA KBD_CHAR_LAST
                LDA #$10
                STA KBD_DB_CNT
				JSR set_repeat_count_long
                plxy
				LDA KBD_CHAR
                SEC
                RTS

;---------------------------------------------------------------
; Same as last key pressed, return NO Key pressed, but dont
; change LAST
same_as_last:
				LDA KBD_RPT_CNT
				BEQ check_hi_is_zero
				DEC KBD_RPT_CNT
				BRA done_same_as_last
check_hi_is_zero:
				LDA KBD_RPT_CNT+1
				BEQ countdown_done
				DEC KBD_RPT_CNT+1
				DEC KBD_RPT_CNT
				BRA done_same_as_last
countdown_done:
				;STZ KBD_CHAR_LAST
				JSR set_repeat_count_short
				plxy
				LDA KBD_CHAR
				SEC
				RTS

done_same_as_last:
				plxy
				LDA #0
				CLC
				RTS

set_repeat_count_short:
				LDA #1
				STA KBD_RPT_CNT+1
				LDA #$7F
				STA KBD_RPT_CNT
				RTS

set_repeat_count_long:
				LDA #4
				STA KBD_RPT_CNT+1
				LDA #$2F
				STA KBD_RPT_CNT
				RTS

;---------------------------------------------------------------
; kbd_iskey - check if key given by keycode in X is pressed
;
; 			keycode: bits( SCrrrccc ) Shift, Ctrl, Row(3bits), Col(3bits)
kbd_iskey:
				STA KBD_CODE				; has key-code
; ignore shift/ctrl flags just check actual key press

kik_decode_row:
				STZ KBD_ROW				; clear result row
				LDA KBD_CODE			; key-code
				LSR						; get bits 4,5,6
				LSR
				LSR
				AND #$07				; A has encoded row
				BEQ kik_decode_col		; if row=0 done

				INC KBD_ROW				; set bit 0 of result
@loop1:			; shift result left row number of times
				ASL KBD_ROW
				DEC
				BNE @loop1
				
kik_decode_col:
				STZ KBD_COL				; clear result col
				LDA KBD_CODE
				AND #$07				; mask lower 3 bits to get encoded col
				BEQ kik_check_key		; if col=0 done

				INC KBD_COL				; set bit 0 of result
@loop2:			; shift result left col number of times
				ASL KBD_COL
				DEC
				BNE @loop2
				
kik_check_key:	LDA KBD_ROW				; load row bit
				STA VIA1+VIA_ORA        ; Write 0s to ALL rows
				LDA VIA1+VIA_IRB        ; Read columns
				CMP KBD_COL				; compare to column bit
				BNE kik_done 	        ; not matched key

				SEC
				RTS
kik_done:
				CLC
				RTS

;---------------------------------------------------------------
; kbd_getkey - return "keycode" in KBD_ROW, KBD_COL Carry is 0 if no key
kbd_getkey:
				STZ KBD_ROW				; result row
				STZ KBD_COL				; result col

                phxy
				LDA #0					   ; 1st test all rows to see if anything is pressed
				STA VIA1+VIA_ORA           ; Write 0s to ALL rows
				LDA VIA1+VIA_IRB           ; Read columns
                CMP #$FF
                BNE kgk_getkey             ; Not all 1s means found a key pressed
kgk_nokey:
				LDA #$FF                   ; Disconnect rows
                STA VIA1+VIA_ORA
				plxy
			    CLC
				RTS
kgk_getkey:
                LDX #7
                LDA #%01111111    ; Bit7 of B corresponds to Row A above
				STA KBD_CHAR	  ; store in temp, we'll ROR it later to test each row
@save_loop:     STA VIA1+VIA_ORA       ; select a row
				LDA VIA1+VIA_IRB       ; read column
                EOR #$FF            ; invert
                STA scan_buffer,X ; and store for later interpretation
                SEC               ; move on
				ROR KBD_CHAR      ; to next row
                LDA KBD_CHAR
                DEX
                BPL @save_loop

				LDA #$FF          ; Disconnect rows
                STA VIA1+VIA_ORA
				LDA #0			  ; done with temp var
				STA KBD_CHAR

; set KBD_ROW and KBD_COL
;  First KBD_ROW
kgk_set_outvars:
                LDX #7
                LDA #0
@loop1:         LDA scan_buffer,X   ; check each column scanned
                BNE @isset          ; if it has any cols set put 1 in KBD_ROW

@notset:        CLC                 ; otherwise put 0
                ROL KBD_ROW
                BRA @over

@isset:         SEC
                ROL KBD_ROW

@over:          DEX                 ; next
                BPL @loop1

; Make KBD_COL an OR of all columns
                LDX #7
                LDA #0
@loop2:         ORA scan_buffer,X
                DEX
                BPL @loop2
                STA KBD_COL

				plxy
                SEC
				RTS

