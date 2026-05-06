GAME=hello2
MAIN=hello2
SOURCES := \
../acia.s \
../string.s \
../print_util.s \
../bcd.s \
../video_common.s \
../video.s \
../sprite.s

all: $(GAME)

$(GAME).o: $(MAIN).s
	ca65 -g -s -o $@ -l  $(@:.o=.lst) $(DEFINES) $<

%.o: %.s ../video_chartable_1.inc65 ../zeropage.inc65
	ca65 -g -s -o $@ -l $(@:.o=.lst) $(DEFINES) $<

$(GAME): $(GAME).o $(SOURCES:.s=.o)
	cl65 -vm -g -T -C $(GAME).cfg $(LIBS) -t none -o $@ -m $(GAME).map -l $(GAME).lst -Ln $(GAME).vice -v $^

install: $(GAME)
	cp $(GAME) ../SDCARD/DISK3/


clean:
	rm -f $(GAME) *.o *.lst *map *vice
