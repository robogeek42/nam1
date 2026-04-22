make clean
export VDP=1
export PS2K=1
export SDIO=1
export SOUND=1
#export PONG=1
#export PACMAN=1
export FASTCPU=1
#export DEBUG_PRINT_SD=1
#export DEBUG_PRINT_SOUND=1
make all
cp firmware homebrew.bin
