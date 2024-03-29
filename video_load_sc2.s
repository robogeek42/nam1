		.setcpu "65C02"
        .include "zeropage.inc65"
        .include "macros.inc65"
		.include "video_common.inc65"
		.include "video_registers.inc65"
        .include "video.inc65"

        .export vdp_load_sc2

.code


vdp_load_sc2:
                JSR vdp_setaddr_pattern_table

                ld16 TMP0, PT_BLK0
                JSR vls_write_block

                JSR vdp_setaddr_color_table_g2
                
                ld16 TMP0, CT_BLK0
                JSR vls_write_block
    
                ;; load name table to consective names
                JSR vdp_load_number_name_table

                RTS

vls_write_block:
                LDX #24             ;; write 24 blocks of 256 (3*2K)
                LDY #00
vls_loop1:      LDA (TMP0),Y
                JSR vdp_write
                INY
                BNE vls_loop1
                INC TMP0+1          ;; inc char addr by 256
                DEX
                BNE vls_loop1
                RTS


;.include "resources/alien.inc65"
;.include "resources/stourbridge.inc65"
;.include "resources/suzanne.inc65"
;.include "resources/victoria_principal.inc65"
;.include "resources/flowers1.inc65"
;.include "resources/flowers2.inc65"
;.include "resources/80sClassic.inc65"
.include "resources/smashmario.inc65"

