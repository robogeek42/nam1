
5 REM find greatest common divisor (with user supplied values)
20 INPUT "Enter A: ";A : INPUT "Enter B: ";B
25 IF (A<=0 OR B<=0 OR INT(A)<>A OR INT(B)<>B) THEN HOME : GOTO 20 : RE
30 IF A < B THEN C = A : A=B : B=C
40 PRINT A,B
50 LET C = A - INT(A/B)*B
60 LET A = B : B = C
70 IF B > 0 GOTO 40
80 PRINT "GCG is ";A
90 END
