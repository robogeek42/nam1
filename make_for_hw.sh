make clean
export VDP=1
export PS2K=1
export SDIO=1
export SOUND=1
export FASTCPU=1
#export DEBUG_PRINT_SD=1
#export DEBUG_PRINT_SOUND=1
make all

cp firmware homebrew.bin

python get_symbols.py

if false
then
    echo "============= Make App Hello2 ==================="
    # Hello2
    cd hello2
    make clean install
    cd -
fi
if false
then
    echo "============= Make App Hello ==================="
    # Hello
    cd hello
    make clean install
    cd -
fi

if true
then
    echo "============= Make App Pacman ==================="
    # Pacman
    cd pacman
    make clean install
    cd -
fi

if false
then
    echo "============= Make App Pong ==================="
    # Pong
    cd pong
    make clean install
    cd -
fi

if false
then
    echo "============= Make App Breakout ==================="
    # Breakout
    cd breakout
    make clean install
    cd -
fi
