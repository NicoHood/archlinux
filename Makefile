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
	install -Dm755 bin/nicohood.restore.sh $(DESTDIR)$(BINDIR)/nicohood.restore.sh
	install -Dm755 bin/nicohood.clone.sh $(DESTDIR)$(BINDIR)/nicohood.clone.sh
	install -Dm755 bin/nicohood.common.sh $(DESTDIR)$(BINDIR)/nicohood.common.sh
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	ln -sf $(BINDIR)/nicohood.mkfs.sh $(DESTDIR)$(PREFIX)/bin/nicohood.mkfs
	ln -sf $(BINDIR)/nicohood.mount.sh $(DESTDIR)$(PREFIX)/bin/nicohood.mount
	ln -sf $(BINDIR)/nicohood.install.sh $(DESTDIR)$(PREFIX)/bin/nicohood.install
	ln -sf $(BINDIR)/nicohood.restore.sh $(DESTDIR)$(PREFIX)/bin/nicohood.restore
	ln -sf $(BINDIR)/nicohood.clone.sh $(DESTDIR)$(PREFIX)/bin/nicohood.clone
	ln -sf $(BINDIR)/nicohood.common.sh $(DESTDIR)$(PREFIX)/bin/nicohood.common
	cp -r pkg $(DESTDIR)$(BINDIR)/
	install -Dm644 Readme.md $(DESTDIR)$(PREFIX)/share/doc/nicohood/Readme.md

uninstall:
	rm -rf $(DESTDIR)$(BINDIR)
	rm -f $(DESTDIR)$(PREFIX)/bin/nicohood.mkfs
	rm -f $(DESTDIR)$(PREFIX)/bin/nicohood.mount
	rm -f $(DESTDIR)$(PREFIX)/bin/nicohood.install
	rm -f $(DESTDIR)$(PREFIX)/bin/nicohood.restore
	rm -f $(DESTDIR)$(PREFIX)/bin/nicohood.clone
	rm -f $(DESTDIR)$(BINDIR)/common.sh
	rm -f $(DESTDIR)$(PREFIX)/share/doc/nicohood/Readme.md
