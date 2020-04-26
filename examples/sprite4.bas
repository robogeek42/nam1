10 MODE 1
20 COL 4,15
30 DIM BUF(2)
40 S=0:P=0:A=0:Y=0
50 I=0:D=0:M=0

110 RESTORE 900
120 SPR T 0
130 FOR S=0 TO 1
140 P=S
150 GOSUB 1000
160 NEXT S

210 SPR X 0, 20, 50 : SPR C 0,4 
220 SPR X 1, 40, 50 : SPR C 1,6
230 SPR E 0
240 SPR E 1
250 FOR I=20 TO 60 STEP 1
260 SPR X 0, I, 50
270 DELAY 20
280 GOSUB 800
290 NEXT I

699 END
700 CURS 0,0 : PRINT "COLLISION" : RETURN
710 CURS 0,0 : PRINT "          " : RETURN
720 CURS 0,1 : PRINT "FIFTH ";(SS AND $1F) : RETURN
730 CURS 0,1 : PRINT "          " : RETURN

800 SS=SSTATUS
810 IF (SS AND $20)>0 THEN GOSUB 700 ELSE GOSUB 710
820 IF (SS AND $40)>0 THEN GOSUB 720 ELSE GOSUB 730
830 RETURN

900 DATA $03, $06, $0C, $18, $30, $60, $C0, $80
901 DATA $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
1000 REM Load sprite
1020 BADDR=VARPTR(BUF(0))
1030 FOR I=0 TO 7 : READ D : POKE BADDR+I, D : NEXT
1040 SPR L BADDR, P
1050 SPR P S,P
1060 RETURN
