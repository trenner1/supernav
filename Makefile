APP := $(HOME)/Applications/SuperNav.app
AGENT := $(HOME)/Library/LaunchAgents/local.supernav.plist
IDENTITY ?= SuperNav Signing
SDK ?= $(shell xcrun --sdk macosx --show-sdk-path)
NOTARY_PROFILE ?= supernav-notary
RELEASE_IDENTITY ?=

build:
	./scripts/build-icon.sh
	mkdir -p build/SuperNav.app/Contents/MacOS build/SuperNav.app/Contents/Resources
	swiftc -O -swift-version 5 -sdk $(SDK) *.swift -o build/SuperNav.app/Contents/MacOS/SuperNav
	cp Info.plist build/SuperNav.app/Contents/Info.plist
	cp build/AppIcon.icns build/SuperNav.app/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(IDENTITY)" build/SuperNav.app

install: build
	-pkill -x SuperNav
	mkdir -p $(HOME)/Applications
	rm -rf $(APP)
	cp -R build/SuperNav.app $(APP)
	sed 's|APP_PATH|$(APP)|' local.supernav.plist > $(AGENT)
	-launchctl bootout gui/$$(id -u) $(AGENT)
	launchctl bootstrap gui/$$(id -u) $(AGENT)

release:
	@RELEASE_IDENTITY="$(RELEASE_IDENTITY)" NOTARY_PROFILE="$(NOTARY_PROFILE)" SDK="$(SDK)" ./scripts/release.sh

uninstall:
	-launchctl bootout gui/$$(id -u) $(AGENT)
	-pkill -x SuperNav
	rm -rf $(APP) $(AGENT)

.PHONY: build install release uninstall
