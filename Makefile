SOURCES = \
acia.s65 \
string.s65 \
video_common.s65 \
video.s65 \
print_util.s65 \
sprite.s65 \
sd.s65 \
kbdvia.s65 \
bcd.s65 \
pong.s65 \
decomp.s65

# May need to set CC65_LIB to path to compiler libs
ifdef CC65_LIB
	LIBS = -L $(CC65_LIB)
else
	LIBS = 
endif

DEFINES = $(SDIO_DEF) $(KEYB_DEF)
ifdef SDIO
	SDIO_DEF = -D SDIO=$(SDIO)
endif
ifdef KEYB
	KEYB_DEF = -D KEYB=$(KEYB)
endif

all: firmware

main.o: main.s65 basic.asm
	ca65 --feature labels_without_colons -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

%.o: %.s65 video_chartable_1.inc65
	ca65 --feature labels_without_colons -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

firmware: main.o $(SOURCES:.s65=.o)
	cl65 -vm -g -T -C firmware.cfg $(LIBS) -t none -o $@ -m firmware.map -l firmware.lst -Ln firmware.vice $^

clean:
	 rm -f firmware *.o *.lst

install: firmware
	cp firmware $(SYMON_ROOT)/homebrew.bin
