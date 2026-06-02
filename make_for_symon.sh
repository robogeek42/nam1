make clean
export VDP=1
export VKEYB=1
export SOUND=1
export FASTCPU=1
make all
echo "copy to ../symon/homebrew.bin"
cp firmware ../symon/homebrew.bin

python get_symbols.py

if [ "X$APP_HELLO" != "X" ]
then
    echo "============= Make App Hello ==================="
    # Hello
    cd hello
    make clean all
    cd -
fi

if [ "X$APP_PACMAN" != "X" ]
then
    echo "============= Make App Pacman ==================="
    # Pacman
    cd pacman
    make clean all
    cd -
fi

if [ "X$APP_PONG" != "X" ]
then
    echo "============= Make App Pong ==================="
    # Pong
    cd pong
    make clean all
    cd -
fi

if [ "X$APP_BREAKOUT" != "X" ]
then
    echo "============= Make App Breakout ==================="
    # Breakout
    cd breakout
    make clean all
    cd -
fi
