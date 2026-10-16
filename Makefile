# CapsJump. `make test` runs the unit tests; `make app` builds CapsJump.app signed
# ad hoc (every rebuild asks for the permissions again; releases are signed and keep them);
# `make install-local` puts that build in ~/Applications and the CLI in ~/.local/bin, and
# clears the previous build's permission entries so `capsjump setup` asks afresh.

APP := .build/bundle/CapsJump.app
APPS_DIR := $(HOME)/Applications
BIN_DIR := $(HOME)/.local/bin
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: help test app install-local clean

help:
	@echo "make test           run the unit tests"
	@echo "make app            build $(APP), signed ad hoc"
	@echo "make install-local  build, then install to $(APPS_DIR) and link the CLI into $(BIN_DIR)"
	@echo "make clean          remove .build"

test:
	swift test

app:
	scripts/bundle.sh

install-local: app
	@pkill -x CapsJump || true
	rm -rf "$(APPS_DIR)/CapsJump.app"
	mkdir -p "$(APPS_DIR)" "$(BIN_DIR)"
	ditto "$(APP)" "$(APPS_DIR)/CapsJump.app"
	"$(LSREGISTER)" -f "$(APPS_DIR)/CapsJump.app"
	@# The grants of the previous ad hoc build stay listed, switched on, and no longer apply.
	tccutil reset Accessibility ai.stigmer.capsjump
	tccutil reset AppleEvents ai.stigmer.capsjump
	ln -sf "$(APPS_DIR)/CapsJump.app/Contents/Helpers/capsjump" "$(BIN_DIR)/capsjump"
	@echo "installed $(APPS_DIR)/CapsJump.app; CLI at $(BIN_DIR)/capsjump"
	@echo "next: capsjump setup (a local build asks for its permissions again after every rebuild)"

clean:
	rm -rf .build
