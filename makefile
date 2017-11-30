PREFIX?=$(DESTDIR)/usr/local
BINDIR?=$(PREFIX)/bin
SHRDIR?=$(PREFIX)/share

install:
	install -D mkwin.sh $(BINDIR)/mkwin

uninstall:
	-rm -f $(BINDIR)/mkwin

.PHONY: install uninstall
