PREFIX ?= $(HOME)/.local
BIN_DIR := $(PREFIX)/bin

.PHONY: install uninstall test lint

install:
	chmod +x install.sh bin/tmux-phoenix
	PREFIX="$(PREFIX)" ./install.sh

uninstall:
	./bin/tmux-phoenix uninstall
	rm -f "$(BIN_DIR)/tmux-phoenix" "$(BIN_DIR)/tpx"

test:
	chmod +x bin/tmux-phoenix tests/test_snapshots.sh
	./tests/test_snapshots.sh

lint:
	shellcheck bin/tmux-phoenix install.sh tests/test_snapshots.sh
