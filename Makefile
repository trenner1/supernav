APP := $(HOME)/Applications/SuperNav.app
AGENT := $(HOME)/Library/LaunchAgents/local.supernav.plist
IDENTITY ?= SuperNav Signing
SDK ?=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

build:
	mkdir -p build/SuperNav.app/Contents/MacOS
	swiftc -O -swift-version 5 -sdk $(SDK) main.swift -o build/SuperNav.app/Contents/MacOS/SuperNav
	cp Info.plist build/SuperNav.app/Contents/Info.plist
	codesign --force --sign "$(IDENTITY)" build/SuperNav.app

install: build
	-pkill -x SuperNav
	mkdir -p $(HOME)/Applications
	rm -rf $(APP)
	cp -R build/SuperNav.app $(APP)
	sed 's|APP_PATH|$(APP)|' local.supernav.plist > $(AGENT)
	-launchctl bootout gui/$$(id -u) $(AGENT)
	launchctl bootstrap gui/$$(id -u) $(AGENT)

uninstall:
	-launchctl bootout gui/$$(id -u) $(AGENT)
	-pkill -x SuperNav
	rm -rf $(APP) $(AGENT)

.PHONY: build install uninstall
