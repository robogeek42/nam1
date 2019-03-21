10 MODE 2
20 TEXTCOL 15,0
30 DIM BUF(8)
40 S=0:P=0:A=0:B=0
50 I=0:J=0:D=0

100 SPR_SET_TYPE 3
110 PRINT "Load sprite data"
120 FOR P=0 TO (4*3*3)-1
130 GOSUB 1000
140 NEXT
150 PRINT "Setup sprite"
160 SPR_ENABLE 3
180 SPR_COLOUR 0, 6
190 SPR_COLOUR 1, 11
200 SPR_COLOUR 2, 4

250 FOR I=0 TO 192 STEP 4
260 SPR_POS 0,I,100
270 SPR_POS 1,I,100
280 SPR_POS 2,I,100
290 B=(B+1) AND 3
300 IF B=0 THEN RESTORE 2500
305 READ A
310 GOSUB 1100
320 FOR J=0 TO 100
330 D=D*1
340 NEXT
350 NEXT

998 PRINT "End."
999 END
1000 REM Load 16x16 sprite
1020 BADDR=VARPTR(BUF(0))
1030 FOR J=0 TO 7
1040 READ D
1050 POKE BADDR+J, D
1060 NEXT
1080 SPR_LOADP BADDR, P
1090 RETURN

1100 REM Set Anim sprite
1110 SPR_PATTERN 0, A
1120 SPR_PATTERN 1, A+4
1130 SPR_PATTERN 2, A+8
1140 RETURN

2000 REM 3 colour 16x16 mario
2010 REM --- Slot 2
2020 REM color 6 - red
2030 DATA $07,$0F,$00,$00,$00,$06,$02,$03
2040 DATA $03,$07,$03,$03,$0D,$06,$00,$00
2050 DATA $C0,$F0,$00,$00,$00,$00,$40,$20
2060 DATA $A0,$A0,$E0,$E0,$F0,$60,$00,$00
2070 REM color 11 - light yellow (skin)
2080 DATA $00,$00,$01,$03,$03,$01,$00,$00
2090 DATA $00,$00,$1C,$18,$00,$00,$00,$00
2100 DATA $00,$00,$60,$F0,$00,$C0,$0C,$1C
2110 DATA $00,$00,$00,$00,$00,$00,$00,$00
2120 REM color 4 - blue
2130 DATA $00,$00,$0E,$0C,$0C,$00,$0D,$1C
2140 DATA $1C,$18,$00,$04,$32,$78,$30,$18
2150 DATA $00,$00,$80,$00,$E0,$00,$80,$C0
2160 DATA $58,$50,$00,$00,$04,$1C,$38,$00
2170 REM --- Slot 1
2180 REM color 6
2190 DATA $0F,$1F,$00,$00,$00,$0C,$09,$08
2200 DATA $08,$0C,$0C,$0F,$07,$07,$00,$00
2210 DATA $80,$E0,$00,$00,$00,$00,$80,$C0
2220 DATA $C0,$00,$30,$F0,$20,$00,$00,$00
2230 REM color 11
2240 DATA $00,$00,$02,$07,$06,$03,$00,$00
2250 DATA $00,$00,$01,$00,$00,$00,$00,$00
2260 DATA $00,$00,$C0,$E0,$00,$80,$00,$00
2270 DATA $00,$C0,$C0,$00,$00,$00,$00,$00
2280 REM color 4
2290 DATA $00,$00,$1D,$38,$19,$00,$06,$07
2300 DATA $07,$03,$02,$00,$00,$00,$07,$03
2310 DATA $00,$00,$00,$00,$C0,$00,$40,$20
2320 DATA $20,$20,$00,$00,$C0,$E0,$70,$80
2330 REM --- Slot 2
2340 REM color 6
2350 DATA $03,$07,$00,$00,$00,$02,$02,$06
2360 DATA $06,$07,$07,$07,$07,$00,$00,$00
2370 DATA $E0,$F8,$00,$00,$00,$00,$40,$20
2380 DATA $00,$00,$E0,$80,$70,$70,$10,$00
2390 REM color 11
2400 DATA $00,$00,$00,$01,$01,$01,$00,$00
2410 DATA $00,$00,$00,$00,$00,$00,$00,$00
2420 DATA $00,$00,$B0,$F8,$00,$C0,$00,$00
2430 DATA $18,$18,$00,$00,$00,$00,$00,$00
2440 REM color 4
2450 DATA $00,$00,$07,$06,$06,$00,$05,$09
2460 DATA $09,$00,$00,$00,$08,$1F,$1C,$18
2470 DATA $00,$00,$40,$00,$F0,$00,$80,$C0
2480 DATA $E0,$E0,$00,$60,$80,$00,$60,$78

2500 DATA 12,0,12,24
