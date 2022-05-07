100 REM BASIC Month 6: The Mandelbaum Set
120 REM written by FozzTexx
140 
200 REM === Initialize variables and constants
210 DIM PT(128)
220 GO(0) = 33:GO(1) = 138:GO(2) = 200
230 CM(0) = 1:CM(1) = 0:CM(2) = 0
240 CM(3) = 0:CM(4) = 1:CM(5) = 0
250 CM(6) = 0:CM(7) = 0:CM(8) = 1
260 GW = GO(2) * GO(2) / GO(1)
270 TH = GO(2) + 5:GOSUB 2630:TH = TH+SZ(1):GOSUB 2630:TH = TH+SZ(1)
280 RZ(0) = 280:RZ(1) = 192:REM Width & height of screen
290 SX = (RZ(0) - RZ(0) * 0.05) / GW:SY = (RZ(1) - RZ(1) * 0.07) / TH
300 SK = SX:IF SY < SK THEN SK = SY

310 MODE 2
330 X = -GW / 2:Y = -GO(2) / 2:GOSUB 2030:REM Translate
340 X = SK:Y = SK:GOSUB 2230:REM Scale
350 X = RZ(0) / 2:Y = RZ(1) / 2:GOSUB 2030:REM Translate
360 GOSUB 2820
370 RESTORE:REM Reset reading of DATA back to first object
380 GOSUB 2630:GOSUB 2720
390 GOSUB 2630
400 X = (GW - SZ(0)) * SK:Y = (GO(2) + SZ(1) + 5) * SK
410 GOSUB 2030:GOSUB 2720:GOSUB 2920
420 GOSUB 2630
430 GX=GO(1)/2:GY=GO(2)/2:GB=GY-GX:OO=GO(2)*GO(2)/GO(1)-GO(1)
440 GOSUB 4510

510 X = -RZ(0) / 2:Y = -RZ(1) / 2:GOSUB 2030:REM Translate
520 A = PI / 2:GOSUB 2130:REM Rotate
530 X = GO(1) / GO(2):Y = X:GOSUB 2230:REM Scale
540 X=RZ(0)/2+(GW/2-GO(1)/2)*SK:Y=RZ(1)/2:GOSUB 2030:REM Translate
550 GOSUB 4510
560 IF HT > 1 THEN GOTO 510
570 GOSUB 4610

999 END

1000 REM === Update current transformation matrix
1010 REM  - Input: 3x3 matrix in 1D array NT
1020 REM  - Updates 3x3 Matrix in 1D array CM
1030 FOR R = 0 TO 2:FOR C = 0 TO 2
1040 NM(R * 3 + C) = 0
1050 FOR K = 0 TO 2
1060 NM(R * 3 + C) = NM(R * 3 + C) + NT(R * 3 + K)*CM(K*3+C)
1070 NEXT K, C, R
1080 FOR K = 0 TO 3 * 3 - 1:CM(K) = NM(K):NEXT K
1090 RETURN

2000 REM === Translate - move origin
2010 REM  - Input: X, Y
2020 REM  - Updates current transformation matrix in CM
2030 NT(0) = 1:NT(1) = 0:NT(2) = X
2040 NT(3) = 0:NT(4) = 1:NT(5) = Y
2050 NT(6) = 0:NT(7) = 0:NT(8) = 1
2060 GOSUB 1030
2070 RETURN

2100 REM === Rotate - rotate drawing space
2110 REM  - Input: Angle in radians in A
2120 REM  - Updates current transformation matrix in CM
2130 NT(0) = COS(A):NT(1) = -SIN(A):NT(2) = 0
2140 NT(3) = -NT(1):NT(4) = NT(0):NT(5) = 0
2150 NT(6) = 0:NT(7) = 0:NT(8) = 1
2160 GOSUB 1030
2170 RETURN

2200 REM === Scale - modify unit lengths of drawing
2210 REM  - Input: X, Y
2220 REM  - Updates current transformation matrix in CM
2230 NT(0) = X:NT(1) = 0:NT(2) = 0
2240 NT(3) = 0:NT(4) = Y:NT(5) = 0
2250 NT(6) = 0:NT(7) = 0:NT(8) = 1
2260 GOSUB 1030
2270 RETURN

2300 REM === Transform single point using current matrix
2310 REM  - Input: X, Y
2320 REM  - Returns transformed point in X and Y
2330 NT(0) = X:NT(1) = Y:NT(2) = 1
2340 FOR R = 0 TO 2
2350 NM(R) = 0
2360 FOR K = 0 TO 2
2370 NM(R) = NM(R) + NT(K) * CM(R * 3 + K)
2380 NEXT K, R
2390 X = NM(0):Y = NM(1)
2400 RETURN

2500 REM === Draw line
2510 REM  - Input: X1,Y1 X2,Y2
2520 X = X1:Y = Y1:GOSUB 2330:A1 = X:B1 = Y
2530 X = X2:Y = Y2:GOSUB 2330:A2 = X:B2 = Y
2540 HPLOT A1,B1 TO A2,B2
2550 RETURN

2600 REM === Load object from DATA
2610 REM  - Reads next object and leaves size in array SZ
2620 REM    and paths in array PT
2630 ZI = 0:READ ZX:SZ(0) = ZX:READ ZY:SZ(1) = ZY
2640 READ ZC:PT(ZI) = ZC:ZI = ZI + 1
2650 IF ZC = 0 THEN RETURN
2660 FOR ZJ = 1 TO ZC:READ ZX:READ ZY
2670 PT(ZI) = ZX:ZI = ZI + 1:PT(ZI) = ZY:ZI = ZI + 1
2680 NEXT ZJ
2690 GOTO 2640

2700 REM === Draw path
2710 REM  - Input: paths to draw in array PT
2720 ZI = 0
2730 ZC = PT(ZI):ZI = ZI + 1:IF ZC = 0 THEN RETURN
2740 X1 = PT(ZI):ZI = ZI + 1:Y1 = PT(ZI):ZI = ZI + 1
2750 FOR ZJ = 1 TO ZC - 1
2760 X2 = PT(ZI):ZI = ZI + 1:Y2 = PT(ZI):ZI = ZI + 1
2770 GOSUB 2520
2780 X1 = X2:Y1 = Y2:NEXT ZJ
2790 GOTO 2730

2800 REM == Save current transformation matrix
2810 REM  Copies array CM to array OM
2820 FOR I = 0 TO 8:OM(I) = CM(I):NEXT I
2830 RETURN

2900 REM == Restore transformation matrix
2910 REM  Copies array OM to array CM
2920 FOR I = 0 TO 8:CM(I) = OM(I):NEXT I
2930 RETURN

3000 REM Mandelbaum arc
3010 REM  - Input: Arc center at CX,CY; Start/end radians in SA,EA
3030 IF (EA < SA) THEN EA = EA + 2 * PI
3040 NW = SZ(0):NH = SZ(1):NS = GO(0) / NW:SH = NH * NS
3050 RO = GO(1) / 2:RI = RO - GO(0)
3060 AL = (EA - SA) * GO(1) / 2:SG = INT(AL / SH)
3070 GA = (EA - SA) / SG
3080 GC = COS(2 * PI - GA):GS = SIN(2 * PI - GA):ZC = COS(0):ZS = SIN(0)
3090 F1 = CX + RI * GC:G1 = CY + RI * GS
3100 F2 = CX + RO * GC:G2 = CY + RO * GS
3110 F3 = CX + RI * ZC:G3 = CY + RI * ZS
3120 F4 = CX + RO * ZC:G4 = CY + RO * ZS
3130 D1 = F3 - F1:D2 = G3 - G1:D3 = F4 - F2:D4 = G4 - G2
3140 L1 = SQR(D1 * D1 + D2 * D2):L2 = SQR(D3 * D3 + D4 * D4)
3150 GOSUB 2820
3160 X = CX:Y = CY:GOSUB 2330:AX = X:AY = Y

3170 REM Walk through PT and draw
3180 FOR SN = 0 TO SG - 1
3190 GOSUB 2920
3200 X = -AX:Y = -AY:GOSUB 2030:REM Translate
3210 A = 2 * PI - (SA + SN * GA):GOSUB 2130:REM Rotate
3220 X = AX:Y = AY:GOSUB 2030:REM Translate
3230 ZI = 0
3240 ZC = PT(ZI):ZI = ZI + 1:IF ZC = 0 THEN GOTO 3350
3250 X1 = PT(ZI) * NS:ZI = ZI + 1
3260 Y1=PT(ZI)*NS*(L1-1+(L2-L1-1)*(X1/GO(0)))/L2:ZI=ZI+1
3270 X1=X1+CX+RI:Y1=Y1+CY
3280 FOR ZJ = 1 TO ZC - 1
3290 X2 = PT(ZI) * NS:ZI = ZI + 1
3300 Y2=PT(ZI)*NS*(L1-1+(L2-L1-1)*(X2/GO(0)))/L2:ZI=ZI+1
3310 X2 = X2 + CX + RI:Y2 = Y2 + CY
3320 GOSUB 2520
3330 X1 = X2:Y1 = Y2:NEXT ZJ
3340 GOTO 3240
3350 NEXT SN
3360 GOSUB 2920
3370 RETURN

4000 REM Mandelbaum line
4010 REM  - Input: Start and end diagonal corners in X1,Y1 and X2,Y2
4030 NW = SZ(0):NH = SZ(1) + 1
4040 XD = X2 - X1:YD = Y2 - Y1
4050 IF XD > 0 AND YD < 0 THEN A = 0:WD = XD:HT = YD
4060 IF XD < 0 AND YD < 0 THEN A = 1.5 * PI:HT = XD:WD = YD
4070 IF XD < 0 AND YD > 0 THEN A = PI:WD = XD:HT = YD
4080 IF XD > 0 AND YD > 0 THEN A = 0.5 * PI:HT = XD:WD = YD
4090 WD = ABS(WD):HT = ABS(HT)
4100 NS = WD / NW:SH = INT(NH * NS)
4110 SG = INT((HT + SH - 1) / SH):SH = HT / SG
4120 SX = GO(0) / NW:SY = SH / NH
4130 GOSUB 2820
4140 AX = X1:AY = Y1:X = X1:Y = Y1:GOSUB 2330:OX = X:OY = Y
4150 X = X2:Y = Y2:GOSUB 2330:XD = X - OX:YD = Y - OY
4160 X = 0:Y = 0:GOSUB 2330
4170 X = -X:Y = -Y:GOSUB 2030:REM Translate
4180 GOSUB 2130:REM Rotate
4190 X = SX:Y = SY
4200 IF (XD < 0 AND YD < 0) OR (XD>0 AND YD>0) THEN Y=SX:X=SY
4210 GOSUB 2230:REM Scale
4220 X = OX:Y = OY:GOSUB 2030:REM Translate

4230 REM Walk through PT and draw
4240 FOR SN = 0 TO SG - 1
4250 ZI = 0
4260 ZC = PT(ZI):ZI = ZI + 1:IF ZC = 0 THEN GOTO 4350
4270 X1 = PT(ZI):ZI = ZI + 1
4280 Y1 = PT(ZI) * (SH - 1) / SH:ZI = ZI + 1
4290 FOR ZJ = 1 TO ZC - 1
4300 X2 = PT(ZI):ZI = ZI + 1
4310 Y2 = PT(ZI) * (SH - 1) / SH - SN * (SH / SY):ZI = ZI + 1
4320 GOSUB 2520
4330 X1 = X2:Y1 = Y2:NEXT ZJ
4340 GOTO 4260
4350 NEXT SN
4360 GOSUB 2920

4370 REM Return height to decide if it's time to stop
4380 X = AX:Y = AY + SH:GOSUB 2330
4390 HT = SQR((X - OX) * (X - OX) + (Y - OY) * (Y - OY))
4400 RETURN

4500 REM === G
4510 CX = GX:CY = GY - GB:SA = 0:EA = PI:GOSUB 3030
4520 X1 = GO(0):Y1 = GY - GB:X2 = 0:Y2 = GY + GB:GOSUB 4030
4530 CX = GX:CY = GY + GB:SA = PI:EA = 0:GOSUB 3030
4540 X1=GO(1):Y1=GY + GB:X2 = GX:Y2 = GY + GB - GO(0):GOSUB 4030
4550 RETURN

4600 REM === O
4610 CX = GX + OO:CY = GY - GB:SA = 0:EA = PI:GOSUB 3030
4620 X1 = GO(0) + OO:Y1 = GY - GB:X2 = OO:Y2 = GY + GB:GOSUB 4030
4630 CX = GX + OO:CY = GY + GB:SA = PI:EA = 0:GOSUB 3030
4640 X1=GO(1)-GO(0)+OO:Y1=GY+GB:X2=GO(1)+OO:Y2=GY-GB:GOSUB4030
4650 RETURN

9010 DATA 39,16,15,3,-16,0,-16,0,-13,3,-13,3,-3,0,-3,0,0,10,0,10
9015 DATA -3,6,-3
9020 DATA 6,-13,10,-13,10,-16,6,-16,3,-16,11,16,-16,12,-16,12
9025 DATA -13,16,-13
9030 DATA 16,0,19,0,19,-13,23,-13,23,-16,19,-16,16,-16,5,25
9035 DATA -16,27,-16
9040 DATA 27,-13,25,-13,25,-16,19,36,-9,33,-10,32,-11,34,-13
9045 DATA 36,-12,39
9050 DATA -12,34,-16,30,-14,29,-11,32,-7,35,-6,36,-5,34,-3,32
9055 DATA -4,29,-4
9060 DATA 34,0,38,-1,39,-5,36,-9,0
9070 DATA 53,16,15,23,-13,23,-16,20,-16,16,-16,13,-16,13,-13
9075 DATA 16,-13,16
9080 DATA -3,13,-3,13,0,23,0,23,-3,20,-3,20,-13,23,-13,18,53
9085 DATA -13,53,-16
9090 DATA 46,-16,43,-16,43,-13,43,-10,43,-6,43,-3,43,0,53,0,53
9095 DATA -3,46,-3
9100 DATA 46,-6,51,-6,51,-10,46,-10,46,-13,53,-13,11,10,-16,7
9105 DATA -16,3,-16
9110 DATA 0,-16,0,-13,3,-13,3,0,7,0,7,-13,10,-13,10,-16,14,37
9115 DATA -16,33,-9
9120 DATA 29,-16,26,-16,26,0,29,0,29,-10,32,-4,34,-4,37,-10,37
9125 DATA 0,40,0,40
9130 DATA -16,37,-16,0
9140 DATA 52,8,5,0,0,0,-8,3,-4,5,-8,5,0,3,10,0,8,-8,6,0,2,7,-4
9145 DATA 9,-4,4,11
9150 DATA 0,11,-8,15,0,15,-8,6,18,-8,16,-8,16,0,18,0,20,-4,18
9155 DATA -8,2,23,-4
9160 DATA 21,-4,4,25,-8,21,-8,21,0,25,0,3,31,0,26,0,26,-8,12,32
9165 DATA -4,35,-4
9170 DATA 36,-5,36,-7,35,-8,32,-8,32,0,35,0,35,0,36,-1,36,-3,35
9175 DATA -4,3,41
9180 DATA 0,39,-8,37,0,2,38,-4,40,-4,6,42,-8,42,-1,44,0,45,0,47
9185 DATA -1,47,-8
9190 DATA 5,48,0,48,-8,50,-4,52,-8,52,0,0
