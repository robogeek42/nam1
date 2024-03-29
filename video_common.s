; Table 2-1 from TMS9918A Datasheet
;
;+--------------------+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+------+
;|                    |                    Bits                       |     | !a1 |  a0  |
;|    Operation       |  0  |  1  |  2  |  3  |  4  |  5  |  6  |  7  | CSW | CSR | MODE | a1  a0  
;|--------------------+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+------|
;|Write to VRAM       |     |     |     |     |     |     |     |     |     |     |      |
;|  Byte 1 Addr Setup | A6  | A7  | A8  | A9  | A10 | A11 | A12 | A13 |  0  |  1  |  1   |        7FC1
;|  Byte 2 Addr Setup |  0  |  1  | A0  | A1  | A2  | A3  | A4  | A5  |  0  |  1  |  1   |        7FC1
;|  Byte 3 Data Write | D0  | D1  | D2  | D3  | D4  | D5  | D6  | D7  |  0  |  1  |  0   | 0   0  7FC0
;|--------------------+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+------|
;|VDP Register Write  |     |     |     |     |     |     |     |     |     |     |      |   
;|  Byte 1 Data Write | D0  | D1  | D2  | D3  | D4  | D5  | D6  | D7  |  0  |  1  |  1   |        7FC1
;|  Byte 2 Reg Write  |  1  |  0  |  0  |  0  |  0  | rs0 | rs1 | rs2 |  0  |  1  |  1   | 0   1  7FC1
;|--------------------+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+------|
;|Read from VRAM      |     |     |     |     |     |     |     |     |     |     |      |
;|  Byte 1 Addr Setup | A6  | A7  | A8  | A9  | A10 | A11 | A12 | A13 |  0  |  1  |  1   |        7FC1
;|  Byte 2 Addr Setup |  0  |  0  | A0  | A1  | A2  | A3  | A4  | A5  |  0  |  1  |  1   |        7FC1
;|  Byte 3 Data Read  | D0  | D1  | D2  | D3  | D4  | D5  | D6  | D7  |  1  |  0  |  0   | 1   0  7FC2
;|--------------------+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+------|
;|Read VDP Status     |     |     |     |     |     |     |     |     |     |     |      |
;|  Byte 1 Data Read  | D0  | D1  | D2  | D3  | D4  | D5  | D6  | D7  |  1  |  0  |  1   | 1   1  7FC3
;+--------------------+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+------+
;
;
.include "video_vars.inc65"
.include "video_registers.inc65"
.include "zeropage.inc65"
.include "macros.inc65"
.include "string.inc65"
.include "acia.inc65"

.export vdp_getstatus
.export vdp_regwrite
.export vdp_set_addr_w
.export vdp_set_addr_r
.export vdp_setaddr_name_table
.export vdp_setaddr_pattern_table
.export vdp_setaddr_pattern_table_g1
.export vdp_setaddr_pattern_table_g2
.export vdp_setaddr_color_table_g1
.export vdp_setaddr_color_table_g2
.export vdp_setaddr_sprite_attribute_table
.export vdp_setaddr_sprite_pattern_table
.export vdp_setaddr_pattern_table_offset
.export vdp_write
.export vdp_read
.export vdp_writex

.bss
VDP_REGS:   .res  8,0
VDP_VARS:   .res  9,0
buff:       .res 12,0

.export VDP_REGS
.export VDP_VARS



.code

;================================================================
; Basic VDP routines
;
; 1. Read Status Register - reads into Acc
vdp_getstatus:   LDA VDP_RD_STATUS
                 STA VDP_STATUS
		 BNE vgs_end
		 NOP
		 LDA VDP_RD_STATUS
                 STA VDP_STATUS
                 ;ld16 R0,buff
                 ;JSR fmt_bin_string
                 ;JSR acia_puts
                 ;JSR acia_put_newline
vgs_end:
                 RTS

; 2. Write VDP Register
; Write a value to one of seven registers
; Data is in Acc, Register number+$80 is in Y
vdp_regwrite:   STA VDP_WR_REG        ; Data
.ifdef FASTCPU
                NOP
                NOP
.endif
                STY VDP_WR_REG        ; Register 80...87
.ifdef FASTCPU
                NOP
                NOP
.endif
                RTS

; 3. Write Address
; Set an address in VRAM. Low byte in Y, High byte in A
; This should be followed by a series of writes to VDP_WR_VRAM
vdp_set_addr_w: AND #$3F
                ORA #$40
                STY VDP_ADDR_SET      ; Address lo byte
.ifdef FASTCPU
                NOP
.endif
                STA VDP_ADDR_SET      ; Address hi byte
.ifdef FASTCPU
                NOP
.endif
                RTS
; 3. Read Address
; Set an address in VRAM. Low byte in Y, High byte in A
; This should be followed by a series of reads from VDP_RD_VRAM
vdp_set_addr_r: AND #$3F
                STY VDP_ADDR_SET      ; Address lo byte
.ifdef FASTCPU
                NOP
                NOP
.endif
                STA VDP_ADDR_SET      ; Address hi byte
.ifdef FASTCPU
                NOP
                NOP
.endif
                RTS
;----------------------------------------------------------------

vdp_setaddr_name_table:
                LDY #00             ;; Set VRAM address to name table (VDP_REG2 * 0x400)
                LDA VDP_REGS+2
                ASL
                ASL
                JSR vdp_set_addr_w
                RTS

vdp_setaddr_pattern_table:
                LDA #0
                STA TMP0
vdp_setaddr_pattern_table_offset:   ;; add TMP0*256 to pattern table address
                LDA VDP_MODE     ;; check mode - mode 2 is different
                CMP #2
                BEQ vdp_setaddr_pattern_table_g2
vdp_setaddr_pattern_table_g1:
                LDY #00             ;; Set VRAM address to VDP_REG4 * 0x800
                LDA VDP_REGS+4
                ASL
                ASL
                ASL
                CLC                 ;; offset
                ADC TMP0
                JSR vdp_set_addr_w
                RTS
vdp_setaddr_pattern_table_g2:
                LDA VDP_REGS+4      ;; Pattern Table
                AND #$04            ;; just want upper bit (of the 3 that are used)
                ASL
                ASL
                ASL
                CLC                 ;; offset
                ADC TMP0
                LDY #00          
                JSR vdp_set_addr_w
                RTS

vdp_setaddr_sprite_attribute_table:
                LDY VDP_SAB
                LDA VDP_SAB+1
                JSR vdp_set_addr_w
                RTS
vdp_setaddr_sprite_pattern_table:
                LDY #0
                LDA VDP_REGS+6   ;; 2k boundaries (*0x800)
                ASL
                ASL
                ASL
                JSR vdp_set_addr_w
                RTS
vdp_setaddr_color_table_g1:
vdp_setaddr_color_table_g2:
                LDA VDP_REGS+3   ;; Color table
                AND #$80            ;; just want upper bit
                CLC
                ROR
                ROR
                LDY #0
                JSR vdp_set_addr_w
                RTS

;----------------------------------------------------------------
; VDP Write VRAM
vdp_write:
                STA VDP_WR_VRAM
                NOP
.ifdef FASTCPU
                NOP
                NOP
                NOP
                NOP
.endif
                RTS
vdp_writex:
                STX VDP_WR_VRAM
                NOP
.ifdef FASTCPU
                NOP
                NOP
                NOP
                NOP
.endif
                RTS
;----------------------------------------------------------------
; VDP Read VRAM
vdp_read:
                NOP
.ifdef FASTCPU
                NOP
.endif
                LDA VDP_RD_VRAM
                RTS
