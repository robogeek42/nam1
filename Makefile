SOURCES := \
acia.s65 \
string.s65 \
video_common.s65 \
video.s65 \
print_util.s65 \
sprite.s65 \
sd.s65 \
kbdvia.s65 \
bcd.s65 \
decomp.s65 \
sound.s65 \
pckybd.s65 

ifdef PONG
$(info ** Compile with PONG game **)
	SOURCES += pong.s65
	PONG_DEF = -D PONG=1
endif
ifdef PACMAN
$(info ** Compile with PACMAN game **)
	SOURCES += pm.s65
	PM_DEF = -D PACMAN=1
endif

ifdef UCHESS2
$(info ** Compile with Micro-Chess II **)
	SOURCES += uchess2.s65
	UC_DEF = -D UCHESS2=1
endif

ifdef IMAGETEST
$(info ** Compile with Image Test **)
	IT_DEF = -D IMAGETEST=1
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

DEFINES = $(SDIO_DEF) $(KEYB_DEF) $(FASTCPU_DEF) $(SOUND_DEF) $(PS2K_DEF) $(UC_DEF) $(PM_DEF) $(PONG_DEF) $(IT_DEF)

ifdef SDIO
$(info ** Compile with SD card support **)
	SDIO_DEF = -D SDIO=$(SDIO)
endif

ifdef KEYB
ifdef PS2K
$(error !!! Error cant have both keyboards enabled !!!)
endif
$(info ** Compile with VIA Keyboard support **)
	KEYB_DEF = -D KEYB=$(KEYB)
endif

ifdef PS2K
$(info ** Compile with PS2 Keyboard support **)
	PS2K_DEF = -D PS2K=$(PS2K)
endif
ifdef FASTCPU
$(info ** Compile with FAST CPU support **)
	FASTCPU_DEF = -D FASTCPU=$(FASTCPU)
endif
ifdef SOUND
$(info ** Compile with SN76489 Sound support on VIA2 **)
	SOUND_DEF = -D SOUND=$(SOUND)
endif


all: firmware

main.o: main.s65 basic.asm
	ca65 --feature labels_without_colons -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

%.o: %.s65 video_chartable_1.inc65
	ca65 --feature labels_without_colons -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

firmware: main.o $(SOURCES:.s65=.o)
	cl65 -vm -g -T -C firmware.cfg $(LIBS) -t none -o $@ -m firmware.map -l firmware.lst -Ln firmware.vice $^

clean:
	 rm -f firmware *.o *.lst *map *vice

install: firmware
	cp firmware $(SYMON_ROOT)/homebrew.bin
