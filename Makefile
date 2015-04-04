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
install-man: nenu.1.gz
	install -D nenu.1.gz ${DESTDIR}${PREFIX}/man/man1/nenu.1.gz

.PHONY:
install-execs: nenu nexec nwindow ntime nbatt
	install -Dm 755 $^ ${DESTDIR}${PREFIX}/bin/

.PHONY:
install: install-man install-execs

.PHONY:
uninstall-man:
	rm ${DESTDIR}${PREFIX}/man/man1/nenu.1.gz

.PHONY:
uninstall-execs:
	rm ${DESTDIR}${PREFIX}/bin/nexec
	rm ${DESTDIR}${PREFIX}/bin/nwindow
	rm ${DESTDIR}${PREFIX}/bin/ntime
	rm ${DESTDIR}${PREFIX}/bin/nbatt

.PHONY:
uninstall: uninstall-man uninstall-execs

