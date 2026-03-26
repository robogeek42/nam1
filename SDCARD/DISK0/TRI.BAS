
5 PRINT "Triangle Numbers"
6 PRINT "----------------"
10 INPUT "Give me a number";A
20 IF A > 1000 THEN PRINT"Too Big!" : GOTO10
30 T=0
40 FOR I=1 TO A
50 T=T+I
60 NEXT I
70 PRINT "Triangle number of ";A;" = ";T
