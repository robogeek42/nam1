make clean
export VDP=1
export VKEYB=1
export SOUND=1
export PONG=1
#export PACMAN=1
export FASTCPU=1
make all
echo "copy to ../symon/homebrew.bin"
cp firmware ../symon/homebrew.bin
