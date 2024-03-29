		.setcpu "65C02"
        .include "zeropage.inc65"
        .include "acia.inc65"
        .include "string.inc65"
        .include "macros.inc65"
        .include "io.inc65"
		.include "video_common.inc65"
		.include "video_registers.inc65"
        .include "print_util.inc65"
        .include "video_load_sc2.inc65"
        .include "video_load_mc.inc65"
        .include "video.inc65"
        .include "sprite.inc65"
        .include "buffer.inc65"
        .export vdp_test_parse

.code

msg_error:  .byte "Error", $0d, $0a, $00

;================================================================
; TEST ROUTINES
;
; Tests :
;   vt 0 PP - Memory test. Write 256 bytes to page PP and read back
;   vt 1 PP - Memory test. Clear page PP to value VV
;   vt 2    - graphics test 1 write chars to screen (modes 0, 1 & 2)
;   vt 3    - load the Graphics Mode 2 picture
;   vt 4    - Multicolor mode test
;   vt 5    - 2 8x8 Sprites moving left to right
;   vt 6    - Animated 3 colour 16x16 sprite

vt_error1:      ld16 R0, msg_error
                JSR acia_puts
                RTS

vdp_test_parse:  ;; Tests - buffer address in TMP2/3

                ;; position 2 should be a space
                LDY #2
                LDA (TMP2),Y
                CMP #' '
                BNE vt_error1
                ;; position 3 is test number
                LDY #3
                LDA (TMP2),Y       ; scan_hex_char expects the char in the Acc
                JSR scan_hex_char  ; result in acc 

                CMP #0
                BEQ test_vec0
                CMP #1
                BEQ test_vec1
                CMP #2
                BEQ test_vec2
                CMP #3
                BEQ test_vec3
                CMP #4
                BEQ test_vec4
                CMP #5
                BEQ test_vec5
                CMP #6
                BEQ test_vec6
                JMP vt_error1
test_vec0:      JMP vt_page_write_read
test_vec1:      JMP vt_page_write
test_vec2:      JMP vdp_gtest1
test_vec3:      JMP vt_load_sc2_pic
test_vec4:      JMP vt_load_mcm_pic
test_vec5:      JMP vdp_sprite_test1
test_vec6:      JMP vdp_sprite_test2
                
vt_page_write_read:
                ;; test 0 expects high byte of address
                ;; vt 0 AA
                ;; position 4 is a space
                LDY #4
                LDA (TMP2),Y
                CMP #' '
                BNE vt_error1
                
                ;; position 5&6 are page address
                ;ld16 R0, buffer + 5
                ld16reg_offset R0, TMP2, 5
                JSR scan_hex        ; scan 2 byte hex value into acc
                STA ZP_TMP0

                JSR vdp_testmem
                RTS
vt_page_write:
                ;; vt 1 AA VV
                LDY #4
                LDA (TMP2),Y
                CMP #' '
                BNE vt_error3
                
                ;; position 5&6 are page address
                ld16reg_offset R0, TMP2, 5
                JSR scan_hex        ; scan 2 byte hex value into acc
                STA ZP_TMP0

                LDY #7
                LDA (TMP2),Y
                CMP #' '
                BNE vt_error3
                
                ;; position 8&9 are page address
                ld16reg_offset R0, TMP2, 8
                JSR scan_hex        ; scan 2 byte hex value into acc
                STA ZP_TMP0+1

                JSR vdp_set_page
                RTS

vt_load_sc2_pic:
                ;; load a mode 2 picture
                LDA #2
                JSR vdp_set_mode
                JSR vdp_load_sc2
                RTS

vt_load_mcm_pic:
                ;; multicolor mode test pic
                LDA #3
                JSR vdp_set_mode
                JSR vdp_load_mc_pic
                RTS
                
vt_error3:      ld16 R0, msg_error
                JSR acia_puts
                RTS

;----------------------------------------------
; Test the VRAM by writing a pattern to memory and reading those values back
; Expect High byte of address in ZP_TMP0
vdp_testmem:    LDY #0                  ;; set VRAM write address
                LDA ZP_TMP0
                JSR vdp_set_addr_w
                LDX #0                  ;; write to 256 consecutive locations
vt1_loop:       STX VDP_WR_VRAM
                INX
                BNE vt1_loop

                ; read back to CPU memory
                ld16 RES, page_buffer   ;; set read-back address
                LDY #0                  ;; set VDP VRAM read address (and test 256 bytes)
                LDA ZP_TMP0
                JSR vdp_set_addr_r
vt1_loop1:      LDA VDP_RD_VRAM         ;; read back
                STA (RES),Y
                INY
                BNE vt1_loop1

                ; print out the page
                LDX #$10            ;; 16*16 bytes
vt1_loop2:      JSR print_memory16  ;; print 16 bytes from (RES) and inc RES by 16
                DEX
                BNE vt1_loop2
                RTS

;----------------------------------------------
; Set all 256 bytes in a page to a given value
; Expect High byte of address in ZP_TMP0 and Byte to write in ZP_TMP0+1
vdp_set_page:   LDY #0                  ;; set VRAM write address
                LDA ZP_TMP0
                JSR vdp_set_addr_w
                LDX #0                  ;; write to 256 consecutive locations
                LDA ZP_TMP0+1
vt2_loop:       STA VDP_WR_VRAM
                INX
                BNE vt2_loop
                RTS

;================================================================
; Graphics Character Test
; write consecutive chars all over screen
vdp_gtest1:     JSR vdp_load_number_name_table
                RTS


;================================================================
; Sprite test - draw two 8x8 sprites and move across screen
;               one sprite is offset left 32 pix using early-clock flag
vdp_sprite_test1:
                ;; load an 8x8 sprite
                JSR spr_set_small
                JSR vdp_setaddr_sprite_pattern_table

                ;; load 8 bytes
                ld16 R0,SPRITE_INV1
gt2_loop:       LDA (R0),Y
                STA VDP_WR_VRAM
                INY
                CPY #8
                BNE gt2_loop

                ;; Sprite 0 - red
                ;; set vertical and horiz position of sprite (centre of screen)
                LDY VDP_SAB      ;; Sprite attribute base address
                LDA VDP_SAB+1
                JSR vdp_set_addr_w
                LDA #96             ;; vertical
                STA VDP_WR_VRAM
                NOP
                LDA #0            ;; Horiz
                STA VDP_WR_VRAM
                NOP
                ;; set sprite pattern, colour and Early Clock (left shift 32)
                LDA #0 
                STA VDP_WR_VRAM     ;; pattern 0
                NOP
                LDA #8              ;; Colour 8 (medium red), No shift
                STA VDP_WR_VRAM

                ;; Sprite 1 - blue
                ;; set vertical and horiz position of sprite (centre of screen)
                LDA #64             ;; vertical
                STA VDP_WR_VRAM
                NOP
                LDA #0            ;; Horiz
                STA VDP_WR_VRAM
                NOP
                ;; set sprite pattern, colour and Early Clock (left shift 32)
                LDA #0 
                STA VDP_WR_VRAM     ;; pattern 0
                NOP
                LDA #$84              ;; Colour 4 (dark blue), shift
                STA VDP_WR_VRAM

                ;; move sprites across sceen
                LDX #0              ;; move from pos 0 to pos 255
                ;; sprite 0
gt2_loop2:      LDY VDP_SAB      ;; Sprite attribute base address
                INY                 ;; horiz field, sprite 0
                LDA VDP_SAB+1
                JSR vdp_set_addr_w
                STX VDP_WR_VRAM 
               
                ;; sprite 1
                CLC
                LDA VDP_SAB
                ADC #5              ;; horiz field of sprite 1
                TAY
                LDA VDP_SAB+1
                JSR vdp_set_addr_w
                STX VDP_WR_VRAM 

                LDY #0              ;;  counter for delay
gt2_delay:      NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                INY
                BNE gt2_delay

                INX
                CPX #0
                BNE gt2_loop2

                RTS

SPRITE_INV1:    .byte $3c, $7e, $5a, $7e, $24, $3c, $66, $c3

;================================================================
; Sprite test 2 - 16x16 3 color sprite with 3 animated positions
;   sprite 0 = anim 0 color A, sprite 1 = anim 0 color B, sprite 2 = anim 0 color C
;   sprite 3 = anim 1 color A, sprite 4 = anim 1 color B, sprite 5 = anim 1 color C
;   sprite 6 = anim 2 color A, sprite 7 = anim 2 color B, sprite 8 = anim 2 color C
vdp_sprite_test2:   
                ;; load a 16x16 sprite
                JSR spr_set_large
                JSR vdp_setaddr_sprite_pattern_table

                ld16 R0, ANIM_SPRITE_DATA
                LDX #$9              ;; 9 16x16 sprites
vst2_loop2:     LDY #$0             
vst2_loop1:     LDA (R0),Y
                STA VDP_WR_VRAM
                INY
                CPY #$20            ;; 32 bytes per sprite
                BNE vst2_loop1
                CLC
                LDA R0
                ADC #$20
                STA R0
                LDA R0+1
                ADC #0
                STA R0+1
                DEX
                BNE vst2_loop2

                ;; use sprite attributes 0,1 and 2
                ;; show sprites patterns 0,1 and 2 (Anim position 0)
                LDY VDP_SAB      ;; Sprite attribute base address
                LDA VDP_SAB+1
                JSR vdp_set_addr_w
                ;; sprite 0 red
                LDA #96             ;; vertical
                STA VDP_WR_VRAM
                LDA #128            ;; Horiz
                STA VDP_WR_VRAM
                LDA #0 
                STA VDP_WR_VRAM     ;; pattern 0
                LDA #6              ;; Colour 6 (red), No shift
                STA VDP_WR_VRAM
                ;; sprite 1 yellow
                LDA #96             ;; vertical
                STA VDP_WR_VRAM
                LDA #128            ;; Horiz
                STA VDP_WR_VRAM
                LDA #4 
                STA VDP_WR_VRAM     ;; pattern 1
                LDA #11             ;; Colour 11 (light yellow), No shift
                STA VDP_WR_VRAM
                ;; sprite 2 blue
                LDA #96             ;; vertical
                STA VDP_WR_VRAM
                LDA #128            ;; Horiz
                STA VDP_WR_VRAM
                LDA #8 
                STA VDP_WR_VRAM     ;; pattern 2
                LDA #4              ;; Colour 4 (blue), No shift
                STA VDP_WR_VRAM
                ;; sprite 3 green
                ;LDA #96             ;; vertical
                ;STA VDP_WR_VRAM
                ;LDA #128            ;; Horiz
                ;STA VDP_WR_VRAM
                ;LDA #3 
                ;STA VDP_WR_VRAM     ;; pattern 3
                ;LDA #2              ;; Colour 2 (green), No shift
                ;STA VDP_WR_VRAM

                RTS
.include "resources/mario_3color_16x16_sprite.inc65"
;.include "resources/test_sprite_4col_16x6.inc65"

