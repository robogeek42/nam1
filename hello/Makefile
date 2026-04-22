NAME=hello

OBJS=

all: $(NAME)

$(NAME).o: $(NAME).s
	ca65 -g -s -o $@ -l $(@:.o=.lst) $<

$(NAME): $(NAME).o $(OBJS)
	cl65 -g -vm -T  -t none -C $(NAME).cfg -o $@ -m $(NAME).map -l final.lst -Ln $(NAME).vice -v $^

clean:
	rm -f $(NAME) *.o *.lst *.map *.vice

install: $(NAME)
	cp $(NAME) ../SDCARD/DISK3/
