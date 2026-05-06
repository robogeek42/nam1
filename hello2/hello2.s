; vim: ts=4 et sw=4

.setcpu "65C02"

.include "../acia.inc65"
.include "../video.inc65"

RES      = $20	; 2 bytes
R0       = $22	; 2 bytes

.code

main:
    lda #<msg_hello
    sta R0
    lda #>msg_hello
    sta R0 + 1

    JSR acia_puts
    JSR vdp_write_text

    JMP main
    ;JMP ($0001)
    ;JMP $8164

msg_hello:
    .byte "Hello World again",$0D,$0A,$00
