DESTDIR?=
PREFIX?=/usr

all: nenu

nenu: nenu.c config.h
	gcc -o nenu nenu.c \
		-lX11 \
		-lXft \
		-lXrender \
		`pkg-config --cflags freetype2` \
		`pkg-config --cflags fontconfig` \
		`pkg-config --libs fontconfig` \
		`pkg-config --libs freetype2` 

.PHONY:
clean:
	rm nenu

.PHONY:
install: nenu nexec nwindow ntime
	install -Dm 755 nenu ${DESTDIR}${PREFIX}/nenu
	install -Dm 755 nexec ${DESTDIR}${PREFIX}/nexec
	install -Dm 755 nwindow ${DESTDIR}${PREFIX}/nwindow
	install -Dm 755 ntime ${DESTDIR}${PREFIX}/ntime

.PHONY:
uninstall:
	rm ${DESTDIR}${PREFIX}/bin/nenu
	rm ${DESTDIR}${PREFIX}/bin/nexec
	rm ${DESTDIR}${PREFIX}/bin/nwindow
	rm ${DESTDIR}${PREFIX}/bin/ntime

