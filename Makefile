SOURCES := \
main.s \
acia.s \
string.s \
video_common.s \
video.s \
print_util.s \
sprite.s \
sd.s \
kbdvia.s \
bcd.s \
decomp.s \
sound.s \
pckybd.s 

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

ifdef IMAGETEST
$(info ** Compile with Image Test **)
	SOURCES += video_load_mc.s
	IT_DEF = -D IMAGETEST=1
	IT_DEFA = --asm-define IMAGETEST=1
endif

ifdef BREAKOUT
$(info ** Compile with BREAKOUT game **)
	SOURCES += breakout.s
	BREAKOUT_DEF = -D BREAKOUT=1
	BREAKOUT_DEFA = --asm-define BREAKOUT=1
endif

# May need to set CC65_LIB to path to compiler libs
ifdef CC65_LIB
	LIBS = -L $(CC65_LIB)
else
	LIBS = 
endif

# Compile with physical keyboard by default as the SIM now supports it
# comodore keyboard now not available
#KEYB ?= 0

DEFINES = $(SDIO_DEF) $(KEYB_DEF) $(FASTCPU_DEF) $(SOUND_DEF) $(PS2K_DEF) $(VKEYB_DEF) $(UC_DEF) $(PM_DEF) $(PONG_DEF) $(IT_DEF) $(BREAKOUT_DEF)
ASMDEFINES = $(SDIO_DEFA) $(KEYB_DEFA) $(FASTCPU_DEFA) $(SOUND_DEFA) $(PS2K_DEFA) $(VKEYB_DEFA) $(UC_DEFA) $(PM_DEFA) $(PONG_DEFA) $(IT_DEFA) $(BREAKOUT_DEFA)
ifdef SDIO
$(info ** Compile with SD card support **)
	SDIO_DEF = -D SDIO=$(SDIO)
	SDIO_DEFA = --asm-define SDIO=$(SDIO)
endif

ifdef KEYB
ifdef PS2K
$(error !!! Error cant have both keyboards enabled !!!)
endif
$(info ** Compile with VIA Keyboard support **)
	KEYB_DEF = -D KEYB=$(KEYB)
	KEYB_DEFA = --asm-define KEYB=$(KEYB)
endif

ifdef PS2K
$(info ** Compile with PS2 Keyboard support **)
	PS2K_DEF = -D PS2K=$(PS2K)
	PS2K_DEFA = --asm-define PS2K=$(PS2K)
endif
ifdef VKEYB
$(info ** Compile with Virtual PS2 Keyboard support **)
	VKEYB_DEF = -D VKEYB=$(VKEYB)
	VKEYB_DEFA = --asm-define VKEYB=$(VKEYB)
endif
ifdef FASTCPU
$(info ** Compile with FAST CPU support **)
	FASTCPU_DEF = -D FASTCPU=$(FASTCPU)
	FASTCPU_DEFA = --asm-define FASTCPU=$(FASTCPU)
endif
ifdef SOUND
$(info ** Compile with SN76489 Sound support on VIA2 **)
	SOUND_DEF = -D SOUND=$(SOUND)
	SOUND_DEFA = --asm-define SOUND=$(SOUND)
endif


all: firmware

main.o: main.s basic.s
	ca65 -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

%.o: %.s video_chartable_1.inc65 zeropage.inc65
	ca65 -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

firmware: main.o $(SOURCES:.s=.o)
	ld65 -vm -C firmware.cfg $(LIBS) -o $@ -m firmware.map -Ln firmware.vice $^

#firmware: $(SOURCES)
#	cl65 -vm -g -T -C firmware.cfg $(LIBS) -t none -o $@ -m firmware.map -l firmware.lst -Ln firmware.vice -v -d $(DEFINES) $(ASMDEFINES) $^

clean:
	 rm -f firmware *.o *.lst *map *vice

install: firmware
	cp firmware $(SYMON_ROOT)/homebrew.bin
