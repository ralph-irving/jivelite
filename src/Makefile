LDFLAGS ?= -lrt
SOURCES ?= platform_linux.c

CFLAGS  += -I. -I$(PREFIX)/include/luajit-$(LUAJIT_VERSION) -I/usr/include/SDL -ISDL_SavePNG -Wall -fPIC
LDFLAGS += -lSDL -lSDL_ttf -lSDL_image -lSDL_gfx -lluajit-5.1 -lm -lpthread
EXE = ../bin/jivelite

DEPS    = jive.h common.h log.h version.h

SOURCES += jive.c jive_event.c jive_font.c jive_group.c jive_icon.c jive_label.c jive_menu.c jive_slider.c jive_style.c jive_surface.c jive_textarea.c jive_textinput.c jive_utils.c jive_widget.c jive_window.c jive_framework.c log.c system.c jive_dns.c jive_debug.c resize.c

OBJECTS = $(SOURCES:.c=.o) visualizer/visualizer.o visualizer/spectrum.o visualizer/vumeter.o visualizer/kiss_fft.o

all: visualizer $(EXE)

visualizer:
	cd visualizer; make

$(EXE): $(OBJECTS)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $@

$(OBJECTS): $(DEPS)

.c.o:
	$(CC) $(CFLAGS) $< -c -o $@

clean:
	rm -f $(OBJECTS) $(EXE)
	cd visualizer; make clean
