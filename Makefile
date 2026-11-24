APP := $(HOME)/Applications/SuperNav.app
AGENT := $(HOME)/Library/LaunchAgents/local.supernav.plist
IDENTITY ?= SuperNav Signing
SDK ?=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

build:
	mkdir -p build/SuperNav.app/Contents/MacOS
	swiftc -O -swift-version 5 -sdk $(SDK) *.swift -o build/SuperNav.app/Contents/MacOS/SuperNav
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

release:
	rm -rf build/release
	mkdir -p build/release/SuperNav.app/Contents/MacOS
	for arch in arm64 x86_64; do \
		swiftc -O -swift-version 5 -sdk $(SDK) -target $$arch-apple-macos14 *.swift -o build/release/$$arch || exit 1; \
	done
	lipo -create -output build/release/SuperNav.app/Contents/MacOS/SuperNav build/release/arm64 build/release/x86_64
	cp Info.plist build/release/SuperNav.app/Contents/Info.plist
	codesign --force --sign "$(IDENTITY)" build/release/SuperNav.app
	cd build/release && ditto -c -k --keepParent SuperNav.app SuperNav.zip

uninstall:
	-launchctl bootout gui/$$(id -u) $(AGENT)
	-pkill -x SuperNav
	rm -rf $(APP) $(AGENT)

.PHONY: build install release uninstall
