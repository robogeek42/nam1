.setcpu "65C02"
.include "zeropage.inc65"
.include "macros.inc65"
.include "video_registers.inc65"
.include "video_common.inc65"
.include "video.inc65"

.export vdp_load_mc_pic

.code

; address of data in TMP1
vdp_load_mc_pic:
                JSR vdp_load_mc_standard_name_table
                JSR vdp_setaddr_pattern_table
                LDX #8
                LDY #0
@loop:          LDA (TMP1),Y
                JSR vdp_write
                INY
                BNE @loop
                INC TMP1+1
                DEX
                BNE @loop

                RTS


