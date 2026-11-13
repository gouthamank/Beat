# Command-line shortcuts. `make install` builds a Release copy and puts it in /Applications.

export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

# This Mac's architecture only: half the compile time of a universal build, and xcodebuild stops
# asking which of several "My Mac" destinations to use.
XCODEBUILD := xcodebuild -project Beat.xcodeproj -scheme Beat -derivedDataPath build -quiet \
	-destination "platform=macOS,arch=$(shell uname -m)" ONLY_ACTIVE_ARCH=YES
# Build number and commit from git, shown in About Beat as "Version 1.0 (42 · a1b2c3d)". The build
# number must be numeric, so it's the commit count; "-dirty" marks a build with uncommitted changes.
GIT_COUNT := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo none)$(shell git status --porcelain 2>/dev/null | grep -q . && echo -dirty)
RELEASE_APP := build/Build/Products/Release/Beat.app
INSTALLED_APP := /Applications/Beat.app

.PHONY: project build test install clean ios-sim-ipad ios-sim-iphone ios-install

# Regenerate Beat.xcodeproj from project.yml.
project:
	xcodegen generate

# Release build into build/.
build: project
	$(XCODEBUILD) -configuration Release CURRENT_PROJECT_VERSION=$(GIT_COUNT) BEAT_COMMIT=$(GIT_COMMIT) build

# Run the unit tests (Debug).
test: project
	$(XCODEBUILD) test

# Release build, replace the installed copy, and relaunch it. Beat is quit politely first so it can
# finish saving; the first run asks once to let Terminal control Beat.
install: build
	@if pgrep -xq Beat; then \
		osascript -e 'tell application "Beat" to quit'; \
		while pgrep -xq Beat; do sleep 0.2; done; \
	fi
	rm -rf "$(INSTALLED_APP)"
	ditto "$(RELEASE_APP)" "$(INSTALLED_APP)"
	open "$(INSTALLED_APP)"

# Delete build products (the installed app is left alone).
clean:
	rm -rf build

# --- iPad and iPhone (the BeatiOS target). The Mac targets above are unchanged.

IOS_BUILD := xcodebuild -project Beat.xcodeproj -scheme BeatiOS -derivedDataPath build/ios -quiet \
	CURRENT_PROJECT_VERSION=$(GIT_COUNT) BEAT_COMMIT=$(GIT_COMMIT)
# Simulators to run on; override with e.g. `make ios-sim-iphone IOS_IPHONE="iPhone 17"`
# (names from `xcrun simctl list devices available`).
IOS_IPAD ?= iPad Pro 13-inch (M5)
IOS_IPHONE ?= iPhone 17 Pro
# A device with a live connection, else the first one on a cable (devicectl opens the connection itself when it
# installs: an idle phone shows as disconnected); override with `make ios-install IOS_DEVICE=<udid>`
# (UDIDs from `xcrun xctrace list devices`).
# Through a temporary file (with /dev/stdout, devicectl's table went into the JSON), and with DEVELOPER_DIR passed
# in: macOS make doesn't export it to $(shell), and the Command Line Tools have no devicectl.
IOS_DEVICE ?= $(shell f=$$(mktemp); DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun devicectl list devices --json-output $$f >/dev/null 2>&1; python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["result"]["devices"]; c=lambda x: x.get("connectionProperties",{}); u=lambda x: x["hardwareProperties"]["udid"]; print(next((u(x) for x in d if c(x).get("tunnelState")=="connected"), next((u(x) for x in d if c(x).get("transportType")=="wired"),"")))' $$f 2>/dev/null; rm -f $$f)

# Debug build for a simulator, installed and launched there. The Simulator has no music library: save audio files to
# Files > On My iPad (or iPhone) > Beat > Music, or copy them into the folder `xcrun simctl get_app_container`
# reports, then relaunch Beat.
define ios_sim
	$(IOS_BUILD) -configuration Debug -destination "platform=iOS Simulator,name=$(1)" build
	xcrun simctl boot "$(1)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install "$(1)" build/ios/Build/Products/Debug-iphonesimulator/Beat.app
	xcrun simctl launch "$(1)" dev.gouthaman.Beat
endef

ios-sim-ipad: project
	$(call ios_sim,$(IOS_IPAD))

ios-sim-iphone: project
	$(call ios_sim,$(IOS_IPHONE))

# Release build for a connected iPad or iPhone, signed with the personal team in Config/Secrets.xcconfig
# (DEVELOPMENT_TEAM; add the Apple ID in Xcode > Settings > Accounts once). With a free Apple ID the install stops
# opening after 7 days: run this again to renew it.
ios-install: project
	@test -n "$(IOS_DEVICE)" || { echo "No device found: connect it by cable, unlock it and trust this Mac."; exit 1; }
	@# For this device, not any iOS device: a free Apple ID's profile lists only devices built for, and an install
	@# from a generic build failed with "This provisioning profile cannot be installed on this device".
	$(IOS_BUILD) -configuration Release -destination "platform=iOS,id=$(IOS_DEVICE)" -allowProvisioningUpdates build
	xcrun devicectl device install app --device "$(IOS_DEVICE)" build/ios/Build/Products/Release-iphoneos/Beat.app

