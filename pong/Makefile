GAME=pong
SOURCES=

DEFINES = $(SDIO_DEF) $(FASTCPU_DEF) $(SOUND_DEF) $(PS2K_DEF) $(VKEYB_DEF) $(VDP_DEF)

ifdef PS2K
$(info ** Compile with PS2 Keyboard support **)
	PS2K_DEF = -D PS2K=$(PS2K) -D PS2KB_OR_VKEYB=1
endif
ifdef VKEYB
$(info ** Compile with Virtual PS2 Keyboard support **)
	VKEYB_DEF = -D VKEYB=$(VKEYB) -D PS2KB_OR_VKEYB=1
endif
ifdef FASTCPU
$(info ** Compile with FAST CPU support **)
	FASTCPU_DEF = -D FASTCPU=$(FASTCPU)
endif
ifdef SOUND
$(info ** Compile with SN76489 Sound support on VIA2 **)
	SOUND_DEF = -D SOUND=$(SOUND)
endif
ifdef VDP
$(info ** Compile with TMS9918 Video Support **)
	VDP_DEF = -D VDP=$(VDP)
endif
all: $(GAME)

$(GAME).o: $(GAME).s
	ca65 -g -s -o $@ -l  $(@:.o=.lst) $(DEFINES) $<

$(GAME): $(GAME).o $(SOURCES:.s=.o)
	cl65 -vm -g -T -C $(GAME).cfg -t none -o $@ -m $(GAME).map -l $(GAME).lst -Ln $(GAME).vice -v $^

install: $(GAME)
	cp $(GAME) ../SDCARD/DISK3/

clean:
	rm -f $(GAME) *.o *.lst *map *vice

