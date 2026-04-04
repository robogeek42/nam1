10 MODE 4
20 PRINT "Mode 4 Colour Test"
30 PRINT
40 DIM C$(16)
50 FOR I=1 TO 15
60 READ C$(I)
70 NEXT
80 FOR I=1 TO 15
90 COL I,15 : PRINT C$(I); : COL 15,I : PRINT C$(I)
100 NEXT
110 COL 15,1
120 END

200 REM Colours
201 DATA "     Black     "
202 DATA " Medium  Green "
203 DATA "  Light Green  "
204 DATA "   Dark Blue   "
205 DATA "  Light Blue   "
206 DATA "   Dark Red    "
207 DATA "     Cyan      "
208 DATA "  Medium Red   "
209 DATA "   Light Red   "
210 DATA "  Dark Yellow  "
211 DATA " Light  Yellow "
212 DATA "  Dark Green   "
213 DATA "    Magenta    "
214 DATA "     Gray      "
215 DATA "    White      "

