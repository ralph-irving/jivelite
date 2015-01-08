# Jivelite makefile

# set PREFIX for location of luajit include and libs
PREFIX ?= /usr/local

all: srcs libs

srcs:
	cd src; PREFIX=$(PREFIX) make

libs: lib

lib:
	cd lib-src; PREFIX=$(PREFIX) make

clean:
	rm -Rf lib
	cd src; make clean
	cd lib-src; make clean

