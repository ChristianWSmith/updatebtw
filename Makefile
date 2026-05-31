SRC = src/updatebtw
LIBS = src/lib/config.sh src/lib/backup.sh src/lib/updater.sh src/lib/silent-boot.sh src/lib/installer.sh
SYSTEMD_UNITS = systemd/updatebtw-update.service systemd/updatebtw-update.timer systemd/updatebtw-boot.service
CONFIG = config/updatebtw.conf

all: installer.sh

installer.sh: build/build-installer.sh $(SRC) $(LIBS) $(SYSTEMD_UNITS) $(CONFIG)
	build/build-installer.sh > installer.sh
	chmod +x installer.sh
	@echo "Generated installer.sh"

test:
	cd tests && ./run-tests.sh

integration:
	cd tests && ./integration/run-integration-tests.sh

clean:
	rm -f installer.sh

.PHONY: all test clean
