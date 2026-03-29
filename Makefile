SOURCES := \
main.s \
acia.s \
string.s \
print_util.s \
bcd.s

# May need to set CC65_LIB to path to compiler libs
ifdef CC65_LIB
	LIBS = -L $(CC65_LIB)
else
	LIBS = 
endif

# Compile with physical keyboard by default as the SIM now supports it
DEFINES = $(DEBUG_PRINT_DEF) $(SDIO_DEF) $(FASTCPU_DEF) $(SOUND_DEF) $(PS2K_DEF) $(VKEYB_DEF) $(UC_DEF) $(PM_DEF) $(PONG_DEF) $(IT_DEF) $(BREAKOUT_DEF) $(VDP_DEF)
ASMDEFINES = $(SDIO_DEFA) $(FASTCPU_DEFA) $(SOUND_DEFA) $(PS2K_DEFA) $(VKEYB_DEFA) $(UC_DEFA) $(PM_DEFA) $(PONG_DEFA) $(IT_DEFA) $(BREAKOUT_DEFA) $(VDP_DEFA)
ifdef DEBUG_PRINT
$(info ** DEBUG_PRINT **)
	DEBUG_PRINT_DEF = -D DEBUG_PRINT=$(DEBUG_PRINT)
endif

ifdef SDIO
$(info ** Compile with SD card support **)
	SOURCES += sd.s
	SDIO_DEF = -D SDIO=$(SDIO)
	SDIO_DEFA = --asm-define SDIO=$(SDIO)
endif

ifdef PS2K
$(info ** Compile with PS2 Keyboard support **)
	SOURCES += pckybd.s
	PS2K_DEF = -D PS2K=$(PS2K) -D PS2KB_OR_VKEYB=1
	PS2K_DEFA = --asm-define PS2K=$(PS2K) --asm-define PS2KB_OR_VKEYB=1
endif
ifdef VKEYB
$(info ** Compile with Virtual PS2 Keyboard support **)
	SOURCES += pckybd.s
	VKEYB_DEF = -D VKEYB=$(VKEYB) -D PS2KB_OR_VKEYB=1
	VKEYB_DEFA = --asm-define VKEYB=$(VKEYB) --asm-define PS2KB_OR_VKEYB=1
endif
ifdef FASTCPU
$(info ** Compile with FAST CPU support **)
	FASTCPU_DEF = -D FASTCPU=$(FASTCPU)
	FASTCPU_DEFA = --asm-define FASTCPU=$(FASTCPU)
endif
ifdef SOUND
$(info ** Compile with SN76489 Sound support on VIA2 **)
	SOURCES += sound.s
	SOUND_DEF = -D SOUND=$(SOUND)
	SOUND_DEFA = --asm-define SOUND=$(SOUND)
endif
ifdef VDP
$(info ** Compile with TMS9918 Video Support **)
	SOURCES += video_common.s
	SOURCES += video.s
	SOURCES += sprite.s
	SOURCES += decomp.s
	VDP_DEF = -D VDP=$(VDP)
	VDP_DEFA = --asm-define VDP=$(VDP)
endif
ifdef IMAGETEST
$(info ** Compile with Image Test **)
	SOURCES += video_load_mc.s
	SOURCES += video_test.s
	IT_DEF = -D IMAGETEST=1
	IT_DEFA = --asm-define IMAGETEST=1
endif

ifdef PONG
$(info ** Compile with PONG game **)
	SOURCES += pong.s
	PONG_DEF = -D PONG=1
	PONG_DEFA = --asm-define PONG=1
endif

ifdef PACMAN
$(info ** Compile with PACMAN game **)
	SOURCES += pm.s
	PM_DEF = -D PACMAN=1
	PM_DEFA = --asm-define PACMAN=1
endif

ifdef UCHESS2
$(info ** Compile with Micro-Chess II **)
	SOURCES += uchess2.s
	UC_DEF = -D UCHESS2=1
	UC_DEFA = --asm-define UCHESS2=1
endif

ifdef BREAKOUT
$(info ** Compile with BREAKOUT game **)
	SOURCES += breakout.s
	BREAKOUT_DEF = -D BREAKOUT=1
	BREAKOUT_DEFA = --asm-define BREAKOUT=1
endif


all: firmware

main.o: main.s basic.s
	ca65 -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

%.o: %.s video_chartable_1.inc65 zeropage.inc65
	ca65 -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

firmware: main.o $(SOURCES:.s=.o)
ifdef SDIO
	cl65 -vm -g -T -C firmware.cfg $(LIBS) -t none -o $@ -m firmware.map -l firmware.lst -Ln firmware.vice -v $^
else
	cl65 -vm -g -T -C firmware_nosd.cfg $(LIBS) -t none -o $@ -m firmware.map -l firmware.lst -Ln firmware.vice -v $^
endif

clean:
	 rm -f firmware *.o *.lst *map *vice

install: firmware
	cp firmware $(SYMON_ROOT)/homebrew.bin
