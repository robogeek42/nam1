make clean
export VDP=1
export VKEYB=1
export SOUND=1
export FASTCPU=1
make all
echo "copy to ../symon/homebrew.bin"
cp firmware ../symon/homebrew.bin

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
