Original conversion code is conv.c
Takes an SC2 file and converts it to an inc65 file
to be included in ca65 ASM code.

convcomp.c does the same but compressed.
The code has a switch that allows either inc65 output or
binary. (Default binary)

The binary file is loaded by function decompRLE1_SC2 in decomp.s
uses my own simple Run Length Encoding compression.
