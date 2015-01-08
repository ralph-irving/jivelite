it: command include library library.so

clean: EXPORT INTERNAL
	rm -f `cat EXPORT INTERNAL`


stdcrypto.h: rc4.h sha1.h md5.h
	touch stdcrypto.h

rc4.o: compile rc4.c rc4.h bytestr.h
	./compile rc4.c

rc4_init.o: compile rc4_init.c rc4.h bytestr.h
	./compile rc4_init.c

md5.h: uint32.h
	touch md5.h

md5_init.o: compile md5_init.c md5.h uint32.h
	./compile md5_init.c

md5_transform.o: compile md5_transform.c md5_internal.h md5.h uint32.h
	./compile md5_transform.c

md5_update.o: compile md5_update.c md5_internal.h md5.h bytestr.h uint32.h
	./compile md5_update.c

md5_final.o: compile md5_final.c md5_internal.h md5.h uint32.h
	./compile md5_final.c

sha1.h: uint32.h
	touch sha1.h

sha1_init.o: compile sha1_init.c sha1.h
	./compile sha1_init.c

sha1_transform.o: compile sha1_transform.c sha1_internal.h sha1.h uint32.h
	./compile sha1_transform.c

sha1_feed.o: compile sha1_feed.c sha1_internal.h sha1.h uint32.h bytestr.h
	./compile sha1_feed.c

sha1_update.o: compile sha1_update.c sha1_internal.h sha1.h
	./compile sha1_update.c

sha1_final.o: compile sha1_final.c sha1_internal.h sha1.h uint32.h
	./compile sha1_final.c

libstdcrypto.a: makelib \
rc4.o rc4_init.o \
md5_init.o md5_transform.o md5_update.o md5_final.o \
sha1_init.o sha1_transform.o sha1_feed.o sha1_update.o sha1_final.o
	./makelib libstdcrypto.a \
	rc4.o rc4_init.o \
	md5_init.o md5_transform.o md5_update.o md5_final.o \
	sha1_init.o sha1_transform.o sha1_feed.o sha1_update.o sha1_final.o


command:

include: rc4.h md5.h sha1.h stdcrypto.h

library: libstdcrypto.a

library.so:
