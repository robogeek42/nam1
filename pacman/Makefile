GAME=pacman
MAIN=pm
SOURCES := \
../acia.s \
../string.s \
../print_util.s \
../bcd.s \
../video_common.s \
../video.s \
../sprite.s

# May need to set CC65_LIB to path to compiler libs
ifdef CC65_LIB
	LIBS = -L $(CC65_LIB)
else
	LIBS = 
endif

DEFINES = $(SDIO_DEF) $(FASTCPU_DEF) $(SOUND_DEF) $(PS2K_DEF) $(VKEYB_DEF) $(VDP_DEF)

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
all: $(GAME)

$(GAME).o: $(MAIN).s
	ca65 -g -s -o $@ -l  $(@:.o=.lst) $(DEFINES) $<

%.o: %.s video_chartable_1.inc65 zeropage.inc65
	ca65 -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

$(GAME): $(GAME).o $(SOURCES:.s=.o)
	cl65 -vm -g -T -C $(GAME).cfg $(LIBS) -t none -o $@ -m $(GAME).map -l $(GAME).lst -Ln $(GAME).vice -v $^

install: $(GAME)
	cp $(GAME) ../SDCARD/DISK3/


clean:
	rm -f $(GAME) *.o *.lst *map *vice

