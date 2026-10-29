# n950-fm: FM radio for Hildon (the N950's WL1273, /dev/radio0).
#
#   make && make install DESTDIR=... PREFIX=/usr          (Leste)
PREFIX ?= /usr
PKG_CONFIG ?= pkg-config
CC ?= cc
MSGFMT ?= msgfmt
LOCALEDIR = $(PREFIX)/share/locale
PKGS = hildon-1 gtk+-2.0 gthread-2.0
LANGS = de

all: n950-fm $(LANGS:=.mo)

n950-fm: n950-fm.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wall -DLOCALEDIR='"$(LOCALEDIR)"' \
	    $$($(PKG_CONFIG) --cflags $(PKGS)) -o $@ n950-fm.c \
	    $(LDFLAGS) $$($(PKG_CONFIG) --libs $(PKGS))

%.mo: %.po
	$(MSGFMT) -o $@ $<

install: all
	install -D -m 755 n950-fm $(DESTDIR)$(PREFIX)/bin/n950-fm
	install -D -m 755 n950-fm-audio $(DESTDIR)$(PREFIX)/bin/n950-fm-audio
	install -D -m 755 n950-fm-test $(DESTDIR)$(PREFIX)/bin/n950-fm-test
	install -D -m 644 n950-fm.default $(DESTDIR)/etc/default/n950-fm
	install -D -m 644 n950-fm.desktop \
	    $(DESTDIR)$(PREFIX)/share/applications/hildon/n950-fm.desktop
	for l in $(LANGS); do \
		install -D -m 644 $$l.mo $(DESTDIR)$(LOCALEDIR)/$$l/LC_MESSAGES/n950-fm.mo; \
	done

clean:
	rm -f n950-fm *.mo

.PHONY: all install clean
