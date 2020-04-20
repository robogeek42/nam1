10 MODE 1
20 COL 4,15
30 DIM BUF(1)
100 S=0:P=0:A=0:Y=0
110 I=0:D=0:M=0
120 RESTORE 900
130 GOSUB 1000

210 SPR E 0
220 SPR C 0,6
230 SPR N 1
240 M=TWOPI/192
250 FOR Y=0 TO 192
260 A=Y*M
270 SPR X 0,144+SIN(A)*112,Y
280 NEXT
400 END

900 DATA $3c, $7e, $5a, $7e, $24, $3c, $66, $c3
1000 REM Load sprite
1020 BADDR=VARPTR(BUF(0))
1025 PRINT "Addr",HEX$(BADDR),BADDR
1030 FOR I=0 TO 7
1040 READ D
1050 POKE BADDR+I, D
1060 NEXT
1080 SPR L BADDR, S
1090 SPR P S,P
1100 RETURN
