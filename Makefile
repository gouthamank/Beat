# Command-line shortcuts. `make install`, `sim`, `test` and `snapshot-record` show a menu in a terminal (or take their
# choice as on=…, e.g. `make install on=mac`); the targets they lead to can also be run directly.

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
# Asks which target a menu target leads to (Scripts/menu.sh): on=… if given, else a menu in a terminal.
MENU := bash Scripts/menu.sh
SUBMAKE := $(MAKE) --no-print-directory

# A bare `make` lists the targets (help, below).
.DEFAULT_GOAL := help

.PHONY: help install sim test snapshot-record project clean mac-build mac-install mac-test mac-test-record mac-test-ui \
	mac-test-ui-record mac-test-run-fixtures ios-sim-ipad ios-sim-iphone ios-install ios-test ios-test-record ios-test-ui

##@ Menus (pick from a list, or give the choice: make install on=mac)

# Every target with a `## description` on its line, under the `##@` headings: this list can't drift from the targets.
help: ## This list
	@awk 'BEGIN { FS = ":.*## " } /^##@/ { printf "\n%s\n", substr($$0, 5) } /^[a-z-]+:.*## / { printf "  make %-23s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo

# Install Beat on the Mac or a connected iPad or iPhone.
install: ## Mac or a connected iPad/iPhone (on=mac|ios)
	@key=$$($(MENU) "Install Beat on" "$(on)" mac="Mac" ios="iPad or iPhone (connected)") && \
		$(SUBMAKE) $$key-install

# Build and launch Beat in a Simulator.
sim: ## iPad or iPhone Simulator (on=ipad|iphone)
	@key=$$($(MENU) "Run Beat in" "$(on)" ipad="iPad Simulator" iphone="iPhone Simulator") && \
		$(SUBMAKE) ios-sim-$$key

# Run tests. "All" runs every suite, carrying on past a failing one.
test: ## Mac, iOS Simulator, Mac UI, iOS UI tests, or all (on=mac|ios|mac-ui|ios-ui|all)
	@key=$$($(MENU) "Run" "$(on)" mac="Mac tests" ios="iOS Simulator tests" mac-ui="Mac UI tests" ios-ui="iOS UI tests" \
			all="All of them") && \
		case $$key in \
			mac) $(SUBMAKE) mac-test ;; \
			ios) $(SUBMAKE) ios-test ;; \
			mac-ui) $(SUBMAKE) mac-test-ui ;; \
			ios-ui) $(SUBMAKE) ios-test-ui ;; \
			all) $(SUBMAKE) -k mac-test ios-test mac-test-ui ios-test-ui ;; \
		esac

# Re-record the snapshots or screenshots that changed (after a deliberate design change: look at the failures first).
snapshot-record: ## Re-record changed snapshots: Mac, iOS, or Mac UI screenshots (on=mac|ios|mac-ui)
	@key=$$($(MENU) "Re-record" "$(on)" mac="Mac snapshots" ios="iOS snapshots" mac-ui="Mac UI screenshots") && \
		case $$key in \
			mac) $(SUBMAKE) mac-test-record ;; \
			ios) $(SUBMAKE) ios-test-record ;; \
			mac-ui) $(SUBMAKE) mac-test-ui-record ;; \
		esac

##@ Both platforms

# Regenerate Beat.xcodeproj from project.yml.
project: ## Regenerate Beat.xcodeproj from project.yml
	xcodegen generate

# Delete build products (the installed app is left alone).
clean: ## Delete build products
	rm -rf build

##@ Mac

# Release build into build/.
mac-build: project ## Release build into build/
	$(XCODEBUILD) -configuration Release CURRENT_PROJECT_VERSION=$(GIT_COUNT) BEAT_COMMIT=$(GIT_COMMIT) build

# Release build, replace the installed copy, and relaunch it. Beat is quit politely first so it can
# finish saving; the first run asks once to let Terminal control Beat.
mac-install: mac-build ## Release build into /Applications, relaunched
	@if pgrep -xq Beat; then \
		osascript -e 'tell application "Beat" to quit'; \
		while pgrep -xq Beat; do sleep 0.2; done; \
	fi
	rm -rf "$(INSTALLED_APP)"
	ditto "$(RELEASE_APP)" "$(INSTALLED_APP)"
	open "$(INSTALLED_APP)"

# Run the unit tests (Debug).
mac-test: project ## Unit and snapshot tests
	$(XCODEBUILD) test

# The same, re-recording every snapshot that doesn't match its reference (after a deliberate design change: look at
# the failures from `make mac-test` first). xcodebuild passes TEST_RUNNER_ variables on to the tests without the prefix.
mac-test-record: project ## Re-record the snapshots that changed
	TEST_RUNNER_SNAPSHOT_TESTING_RECORD=failed $(XCODEBUILD) test

# Mac UI tests: launch the UI-test build on the fixture songs, each test in a fresh temporary home, and drive it with
# the keyboard and mouse, so leave the Mac alone while they run. The first run asks once to let the test runner
# control the Mac (System Settings > Privacy & Security > Accessibility).
mac-test-ui: project ## UI tests (leave the Mac alone, about 3 minutes)
	rm -rf /tmp/BeatUITests && mkdir -p /tmp/BeatUITests
	xcodebuild -project Beat.xcodeproj -scheme BeatUITests -derivedDataPath build -quiet \
		-destination "platform=macOS,arch=$(shell uname -m)" ONLY_ACTIVE_ARCH=YES test

# Runs the Mac UI tests, then saves the screenshots they attached (missing references, or ones a design change altered)
# as the new references in BeatUITests/__Snapshots__: the sandboxed test runner can't write to the repo itself. Look at
# the failures from `make mac-test-ui` first; run `make mac-test-ui` again afterwards to check.
mac-test-ui-record: project ## UI tests, then save their changed screenshots
	-$(SUBMAKE) mac-test-ui
	python3 -I Scripts/save-ui-screenshots.py

# The UI-test build (its own bundle ID, so its own settings) on the fixture songs in Fixtures/Library, with its files
# in a temporary home: what a UI test sees, starting fresh. `make mac-test-run-fixtures KEEP=1` reopens it as it was left
# instead (same home and settings), to check what a relaunch keeps. Your own library, pages and settings aren't
# read or touched. Quit it to return.
FIXTURE_HOME := /tmp/beat-fixtures-home
mac-test-run-fixtures: project ## The UI-test build on the fixture songs (KEEP=1: as left)
	$(XCODEBUILD) -configuration UITest build
	$(if $(KEEP),,rm -rf "$(FIXTURE_HOME)" && mkdir -p "$(FIXTURE_HOME)")
	CFFIXED_USER_HOME="$(FIXTURE_HOME)" "build/Build/Products/UITest/Beat.app/Contents/MacOS/Beat" \
		-BeatFixtureLibrary "$(CURDIR)/Fixtures/Library" $(if $(KEEP),,-BeatFreshStart YES)

##@ iPad and iPhone

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

# Debug build, installed and launched in the iPad Simulator.
ios-sim-ipad: project ## Debug build in the iPad Simulator
	$(call ios_sim,$(IOS_IPAD))

# Debug build, installed and launched in the iPhone Simulator.
ios-sim-iphone: project ## Debug build in the iPhone Simulator
	$(call ios_sim,$(IOS_IPHONE))

# Run the unit tests (Debug) inside the iOS app on the iPhone Simulator: the shared tests plus BeatTests/iOS.
ios-test: project ## Unit and snapshot tests in the iPhone Simulator
	@# Booted and ready first: left to boot it, xcodebuild launched the app before the Simulator had finished starting
	@# ("Busy: Application failed preflight checks").
	xcrun simctl bootstatus "$(IOS_IPHONE)" -b
	$(IOS_BUILD) -configuration Debug -destination "platform=iOS Simulator,name=$(IOS_IPHONE)" test

# The same, re-recording every iOS snapshot that doesn't match its reference (see `mac-test-record`).
ios-test-record: project ## Re-record the iOS snapshots that changed
	xcrun simctl bootstatus "$(IOS_IPHONE)" -b
	TEST_RUNNER_SNAPSHOT_TESTING_RECORD=failed $(IOS_BUILD) -configuration Debug -destination "platform=iOS Simulator,name=$(IOS_IPHONE)" test

# UI tests: the UI-test build (on the Simulator its own app, with its own container) on the fixture songs, each test
# starting fresh, driven by taps and swipes. The Simulator is booted first, as for ios-test.
ios-test-ui: project ## UI tests in the iPhone Simulator
	xcrun simctl bootstatus "$(IOS_IPHONE)" -b
	xcodebuild -project Beat.xcodeproj -scheme BeatiOSUITests -derivedDataPath build/ios -quiet \
		-destination "platform=iOS Simulator,name=$(IOS_IPHONE)" test

# Release build for a connected iPad or iPhone, signed with the personal team in Config/Secrets.xcconfig
# (DEVELOPMENT_TEAM; add the Apple ID in Xcode > Settings > Accounts once). With a free Apple ID the install stops
# opening after 7 days: run this again to renew it.
ios-install: project ## Release build onto a connected iPad or iPhone
	@test -n "$(IOS_DEVICE)" || { echo "No device found: connect it by cable, unlock it and trust this Mac."; exit 1; }
	@# For this device, not any iOS device: a free Apple ID's profile lists only devices built for, and an install
	@# from a generic build failed with "This provisioning profile cannot be installed on this device".
	$(IOS_BUILD) -configuration Release -destination "platform=iOS,id=$(IOS_DEVICE)" -allowProvisioningUpdates build
	xcrun devicectl device install app --device "$(IOS_DEVICE)" build/ios/Build/Products/Release-iphoneos/Beat.app
