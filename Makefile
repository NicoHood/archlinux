PREFIX=/usr
MANDIR=$(PREFIX)/share/man
BINDIR=$(PREFIX)/share/nicohood

all:
	@echo "Run 'make install' for installation."
	@echo "Run 'make uninstall' for uninstallation."

install:
	install -Dm755 bin/nicohood.mkfs.sh $(DESTDIR)$(PREFIX)/bin/nicohood.mkfs
	install -Dm755 bin/nicohood.mount.sh $(DESTDIR)$(PREFIX)/bin/nicohood.mount
	install -Dm755 bin/nicohood.install.sh $(DESTDIR)$(PREFIX)/bin/nicohood.install
	install -Dm644 Readme.md $(DESTDIR)$(PREFIX)/share/doc/nicohood/Readme.md

uninstall:
	rm -f  $(DESTDIR)$(PREFIX)/bin/nicohood.mkfs
	rm -f  $(DESTDIR)$(PREFIX)/bin/nicohood.mount
	rm -f  $(DESTDIR)$(PREFIX)/bin/nicohood.install
	rm -f  $(DESTDIR)$(PREFIX)/share/doc/nicohood/Readme.md
