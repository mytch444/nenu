DESTDIR?=
PREFIX?=/usr

all: nenu

nenu: nenu.c config.h
	@gcc -o nenu nenu.c \
		-lX11 \
		-lXft \
		-lXrender \
		-lXinerama \
		`pkg-config --cflags freetype2` \
		`pkg-config --cflags fontconfig` \
		`pkg-config --libs fontconfig` \
		`pkg-config --libs freetype2` 

.PHONY:
clean:
	rm nenu
	rm nenu.1.gz

nenu.1.gz: nenu.1
	gzip -k nenu.1

.PHONY:
install: nenu.1.gz nenu nexec nwindow ntime
	install -Dm 755 nenu ${DESTDIR}${PREFIX}/bin/nenu
	install -Dm 755 nexec ${DESTDIR}${PREFIX}/bin/nexec
	install -Dm 755 nwindow ${DESTDIR}${PREFIX}/bin/nwindow
	install -Dm 755 ntime ${DESTDIR}${PREFIX}/bin/ntime
	install -D nenu.1.gz ${DESTDIR}${PREFIX}/man/man1/nenu.1.gz
	

.PHONY:
uninstall:
	rm ${DESTDIR}${PREFIX}/bin/nenu
	rm ${DESTDIR}${PREFIX}/bin/nexec
	rm ${DESTDIR}${PREFIX}/bin/nwindow
	rm ${DESTDIR}${PREFIX}/bin/ntime
	rm ${DESTDIR}${PREFIX}/man/man1/nenu.1.gz

