CFLAGS  += -I. -I$(PREFIX)/include/luajit-$(LUAJIT_VERSION) -I/usr/include/SDL -Wall -fPIC
LDFLAGS += -lluajit-5.1 -lm -lrt

DEPS    = ../jive.h ../common.h ../log.h

SOURCES += spectrum.c vumeter.c kiss_fft.c visualizer.c

OBJECTS = $(SOURCES:.c=.o)

all: $(OBJECTS)

$(OBJECTS): $(DEPS)

.c.o:
	$(CC) $(CFLAGS) $< -c -o $@

clean:
	rm -f $(OBJECTS)
