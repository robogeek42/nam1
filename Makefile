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
DEFINES = $(DEBUG_PRINT_SD_DEF) $(DEBUG_PRINT_SOUND_DEF) $(SDIO_DEF) $(FASTCPU_DEF) $(SOUND_DEF) $(PS2K_DEF) $(VKEYB_DEF) $(UC_DEF) $(IT_DEF) $(VDP_DEF)
ifdef DEBUG_PRINT_SD
$(info ** DEBUG_PRINT_SD **)
	DEBUG_PRINT_SD_DEF = -D DEBUG_PRINT_SD=$(DEBUG_PRINT_SD)
endif
ifdef DEBUG_PRINT_SOUND
$(info ** DEBUG_PRINT_SOUND **)
	DEBUG_PRINT_SOUND_DEF = -D DEBUG_PRINT_SOUND=$(DEBUG_PRINT_SOUND)
endif

ifdef SDIO
$(info ** Compile with SD card support **)
	SOURCES += sd.s
	SDIO_DEF = -D SDIO=$(SDIO)
endif

ifdef PS2K
$(info ** Compile with PS2 Keyboard support **)
	SOURCES += pckybd.s
	PS2K_DEF = -D PS2K=$(PS2K) -D PS2KB_OR_VKEYB=1
endif
ifdef VKEYB
$(info ** Compile with Virtual PS2 Keyboard support **)
	SOURCES += pckybd.s
	VKEYB_DEF = -D VKEYB=$(VKEYB) -D PS2KB_OR_VKEYB=1
endif
ifdef FASTCPU
$(info ** Compile with FAST CPU support **)
	FASTCPU_DEF = -D FASTCPU=$(FASTCPU)
endif
ifdef SOUND
$(info ** Compile with SN76489 Sound support on VIA2 **)
	SOURCES += sound.s
	SOUND_DEF = -D SOUND=$(SOUND)
endif
ifdef VDP
$(info ** Compile with TMS9918 Video Support **)
	SOURCES += video_common.s
	SOURCES += video.s
	SOURCES += sprite.s
	SOURCES += decomp.s
	VDP_DEF = -D VDP=$(VDP)
endif
ifdef IMAGETEST
$(info ** Compile with Image Test **)
	SOURCES += video_load_mc.s
	SOURCES += video_test.s
	IT_DEF = -D IMAGETEST=1
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
