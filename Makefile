PREFIX=/usr
MANDIR=$(PREFIX)/share/man
BINDIR=$(PREFIX)/share/nicohood

all:
	@echo "Run 'make install' for installation."
	@echo "Run 'make uninstall' for uninstallation."

install:
	install -Dm755 bin/nicohood.mkfs.sh $(DESTDIR)$(BINDIR)/nicohood.mkfs.sh
	install -Dm755 bin/nicohood.mount.sh $(DESTDIR)$(BINDIR)/nicohood.mount.sh
	install -Dm755 bin/nicohood.install.sh $(DESTDIR)$(BINDIR)/nicohood.install.sh
	install -Dm755 bin/common.sh $(DESTDIR)$(BINDIR)/common.sh
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	ln -s $(BINDIR)/nicohood.mkfs.sh $(DESTDIR)$(PREFIX)/bin/nicohood.mkfs
	ln -s $(BINDIR)/nicohood.mount.sh $(DESTDIR)$(PREFIX)/bin/nicohood.mount
	ln -s $(BINDIR)/nicohood.install.sh $(DESTDIR)$(PREFIX)/bin/nicohood.install
	cp -r pkg $(DESTDIR)$(BINDIR)/
	install -Dm644 Readme.md $(DESTDIR)$(PREFIX)/share/doc/nicohood/Readme.md

uninstall:
	rm -rf $(DESTDIR)$(BINDIR)
	rm -f $(DESTDIR)$(PREFIX)/bin/nicohood.mkfs
	rm -f $(DESTDIR)$(PREFIX)/bin/nicohood.mount
	rm -f $(DESTDIR)$(PREFIX)/bin/nicohood.install
	rm -f $(DESTDIR)$(PREFIX)/share/doc/nicohood/Readme.md
