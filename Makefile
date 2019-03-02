SOURCES = \
acia.s65 \
string.s65 \
video_common.s65 \
video.s65 \
main.s65 \
print_util.s65 \
sprite.s65 \
sd.s65 \
kbdvia.s65 \
bcd.s65 \
pong.s65

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

%.o: %.s65 basic.asm
	ca65 --feature labels_without_colons -o $@ -l $(@:.o=.lst) $(DEFINES) $<

all: firmware

firmware: $(SOURCES:.s65=.o)
	cl65 -vm -C firmware.cfg $(LIBS) -t none -o $@ -m map $^

clean:
	 rm -f firmware *.o *.lst

install: firmware
	cp firmware $(SYMON_ROOT)/homebrew.bin
