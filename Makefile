PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/updatebtw
SYSTEMDDIR ?= /etc/systemd/system
CONFDIR ?= /etc/updatebtw

SRC = src/updatebtw
LIBS = src/lib/config.sh src/lib/backup.sh src/lib/updater.sh src/lib/silent-boot.sh src/lib/installer.sh
SYSTEMD_UNITS = systemd/updatebtw-update.service systemd/updatebtw-update.timer systemd/updatebtw-boot.service
CONFIG = config/updatebtw.conf

all: installer.sh

installer.sh: build/build-installer.sh $(SRC) $(LIBS) $(SYSTEMD_UNITS) $(CONFIG)
	build/build-installer.sh > installer.sh
	chmod +x installer.sh
	@echo "Generated installer.sh"
install: $(SRC) $(LIBS) $(SYSTEMD_UNITS) $(CONFIG)
	install -Dm755 src/updatebtw $(DESTDIR)$(BINDIR)/updatebtw
	install -Dm644 src/lib/config.sh $(DESTDIR)$(LIBDIR)/config.sh
	install -Dm644 src/lib/backup.sh $(DESTDIR)$(LIBDIR)/backup.sh
	install -Dm644 src/lib/updater.sh $(DESTDIR)$(LIBDIR)/updater.sh
	install -Dm644 src/lib/silent-boot.sh $(DESTDIR)$(LIBDIR)/silent-boot.sh
	install -Dm644 src/lib/installer.sh $(DESTDIR)$(LIBDIR)/installer.sh
	install -Dm644 systemd/updatebtw-update.service $(DESTDIR)$(SYSTEMDDIR)/updatebtw-update.service
	install -Dm644 systemd/updatebtw-update.timer $(DESTDIR)$(SYSTEMDDIR)/updatebtw-update.timer
	install -Dm644 systemd/updatebtw-boot.service $(DESTDIR)$(SYSTEMDDIR)/updatebtw-boot.service
	install -Dm644 config/updatebtw.conf $(DESTDIR)$(CONFDIR)/updatebtw.conf

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/updatebtw
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -f $(DESTDIR)$(SYSTEMDDIR)/updatebtw-update.service
	rm -f $(DESTDIR)$(SYSTEMDDIR)/updatebtw-update.timer
	rm -f $(DESTDIR)$(SYSTEMDDIR)/updatebtw-boot.service
	rm -rf $(DESTDIR)$(CONFDIR)

test:
	cd tests && ./run-tests.sh

integration:
	cd tests && ./integration/run-integration-tests.sh

clean:
	rm -f installer.sh

.PHONY: all install uninstall test clean
