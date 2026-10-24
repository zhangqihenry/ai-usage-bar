# Convenience wrapper around the scripts in scripts/.
#
#   make build    # compile (debug)
#   make test     # run the self test suite
#   make app      # assemble dist/UsageBar.app (release)
#   make run      # build and launch the app
#   make install  # copy to /Applications and launch
#   make icon     # regenerate Resources/AppIcon.icns
#   make clean    # remove build products
#
# Everything here is a thin alias; the scripts are the source of truth so they
# can also be run directly or from CI.

APP_NAME := UsageBar
APP      := dist/$(APP_NAME).app

.PHONY: build test app run install icon clean lint

build:
	swift build

test:
	swift run UsageBarSelfTest

app:
	scripts/build-app.sh

run: app
	pkill -x $(APP_NAME) 2>/dev/null || true
	open "$(APP)"

install:
	scripts/install.sh

icon:
	swift scripts/make-icon.swift Resources/AppIcon.icns

clean:
	rm -rf .build dist

# Lightweight hygiene check: no tabs, no trailing whitespace in Swift sources.
# BSD grep has no -P, so the tab pattern is built with printf.
lint:
	@if grep -rn "$$(printf '	')" Sources Tests --include='*.swift'; then \
		echo "tabs found in Swift sources"; exit 1; fi
	@if grep -rnE '[[:space:]]+$$' Sources Tests --include='*.swift'; then \
		echo "trailing whitespace found"; exit 1; fi
	@echo "lint OK"
