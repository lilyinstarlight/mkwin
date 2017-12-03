PREFIX?=$(DESTDIR)/usr/local
BINDIR?=$(PREFIX)/bin
SHRDIR?=$(PREFIX)/share

install:
	install -D mkwin.sh $(BINDIR)/mkwin
	install -D mkwin.1 $(SHRDIR)/man/man1/mkwin.1

uninstall:
	-rm -f $(SHRDIR)/man/man1/mkwin.1
	-rm -f $(BINDIR)/mkwin

.PHONY: install uninstall
