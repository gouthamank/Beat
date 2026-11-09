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

.PHONY: project build test install clean

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
