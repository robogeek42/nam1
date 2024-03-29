                    .setcpu "65C02"
                    .include "macros.inc65"
                    .include "zeropage.inc65"

                    .export fmt_hex_char
                    .export fmt_bin_string
                    .export fmt_hex_string
                    .export scan_hex_char
                    .export scan_hex
                    .export scan_hex16

                    .code

; Format the value of the accu as a binary string
; The string is written into (R0)..(R0)+8 (9 bytes)
fmt_bin_string:     sta TMP0
                    phay
                    ldy #8
                    lda #0
                    sta (R0),y
                    dey
@next_bit:          lsr TMP0
                    bcs @bit_is_1
@bit_is_0:          lda #'0'
                    jmp @store_char
@bit_is_1:          lda #'1'
@store_char:        sta (R0),y
                    dey
                    bpl @next_bit
                    play
                    rts

; Convert the 4-bit value of the accu into it's hex ascii character
; The hex ascii character is returned in the accu
fmt_hex_char:       cmp #10
                    bcc @less_then_10
@greater_then_10:   sec
                    sbc #10
                    clc
                    adc #'A'
                    rts
@less_then_10:      clc
                    adc #'0'
                    rts

; Format the value of the accu as a hex string
; The string is written into (R0)..(R0)+2 (3 bytes)
fmt_hex_string:     sta TMP0
                    phay
                    ldy #0
                    lda TMP0
                    lsr
                    lsr
                    lsr
                    lsr
                    jsr fmt_hex_char
                    sta (R0),y
                    iny
                    lda TMP0
                    and #$0f
                    jsr fmt_hex_char
                    sta (R0),y
                    iny
                    lda #0
                    sta (R0),y
                    play
                    rts

; Convert the hex character in the accu to its integer value
; The integer value is returned in the accu
scan_hex_char:      cmp #'0'
                    bcc @invalid
                    cmp #('9' + 1)
                    bcs @no_digit
                    sec
                    sbc #'0'
                    rts
@no_digit:          cmp #'A'
                    bcc @invalid
                    cmp #('F' + 1)
                    bcs @no_upper_hex
                    sec
                    sbc #('A' - 10)
                    rts
@no_upper_hex:      cmp #'a'
                    bcc @invalid
                    cmp #('f' + 1)
                    bcs @invalid
                    sec
                    sbc #('a' - 10)
                    rts
@invalid:           lda #0
                    rts

; Convert two hex characters starting at (R0) into an integer value
; The integer value is returned in the accu
scan_hex:           tya
                    pha
                    ldy #0
                    lda (R0),y
                    jsr scan_hex_char
                    asl
                    asl
                    asl
                    asl
                    sta TMP0
                    iny
                    lda (R0),y
                    jsr scan_hex_char
                    ora TMP0
                    sta TMP0
                    pla
                    tay
                    lda TMP0
                    rts

; Convert four hex characters starting at (R0) into an integer value
; The integer value is returned in RES..RES+1
scan_hex16:         phay
                    ldy #0
                    lda (R0),y
                    jsr scan_hex_char
                    asl
                    asl
                    asl
                    asl
                    sta RES + 1
                    iny
                    lda (R0),y
                    jsr scan_hex_char
                    ora RES + 1
                    sta RES + 1
                    iny
                    lda (R0),y
                    jsr scan_hex_char
                    asl
                    asl
                    asl
                    asl
                    sta RES
                    iny
                    lda (R0),y
                    jsr scan_hex_char
                    ora RES
                    sta RES
                    play
                    rts
