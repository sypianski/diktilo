# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

# Code signing for `make local`. Defaults to ad-hoc ("-"), which regenerates a
# new signature every build — macOS then treats each build as a new app and
# drops previously granted TCC permissions (Accessibility, Input Monitoring,
# Microphone, Screen Recording). To keep permissions across rebuilds, sign with
# a stable self-signed identity by exporting, e.g. in your shell profile:
#     LOCAL_SIGN_IDENTITY="Diktilo Local"
#     LOCAL_SIGN_KEYCHAIN="$HOME/Library/Keychains/diktilo-signing.keychain-db"
LOCAL_SIGN_IDENTITY ?= -
LOCAL_SIGN_KEYCHAIN ?=

# Code signing for `make dmg`/`make notarize` — distribution outside the Mac
# App Store (Developer ID, not sandboxed; see macos/CLAUDE.md for why the App
# Store is off the table: GPLv3 vs. the Store Developer Agreement). Reuses the
# same minimal entitlements as `make local` (no iCloud/push/keychain-group
# capabilities) so no provisioning profile is needed — those capabilities
# require an App ID with matching capabilities enabled and a profile embedded.
DEVELOPER_ID_IDENTITY ?= Developer ID Application: Jakub Sypianski (XD8WV8UBUS)
DEVELOPMENT_TEAM_ID ?= XD8WV8UBUS
NOTARY_PROFILE ?= diktilo-notary
DIST_DERIVED_DATA := $(CURDIR)/.dist-build
DIST_DIR := $(CURDIR)/dist

.PHONY: all clean whisper setup build test-build local check healthcheck help dev run dmg notarize

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build

# Compile the test target without running it. The test host is a full copy
# of the app sharing the installed Diktilo's bundle id, so actually running
# the tests (`test`/`test-without-building`) here would risk clobbering the
# installed app's TCC grants — do that only in a disposable worktree/VM.
test-build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build-for-testing

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building VoiceInk for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	$(eval BUILD_NUMBER := $(shell git rev-list --count HEAD))
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="$(LOCAL_SIGN_IDENTITY)" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		$(if $(LOCAL_SIGN_KEYCHAIN),OTHER_CODE_SIGN_FLAGS="--keychain $(LOCAL_SIGN_KEYCHAIN)",) \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/Diktilo.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying Diktilo.app to ~/Downloads..."; \
		rm -rf "$$HOME/Downloads/Diktilo.app"; \
		ditto "$$APP_PATH" "$$HOME/Downloads/Diktilo.app"; \
		xattr -cr "$$HOME/Downloads/Diktilo.app"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/Diktilo.app"; \
		echo "Run with: open ~/Downloads/Diktilo.app"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Build a notarization-ready, Developer ID-signed .dmg for distribution
# outside the Mac App Store. Does NOT notarize — run `make notarize` after.
dmg: check setup
	@security find-identity -v -p codesigning | grep -q "Developer ID Application" || \
		{ echo "No 'Developer ID Application' identity in the default keychain."; \
		  echo "Xcode -> Settings -> Accounts -> Manage Certificates -> + -> Developer ID Application"; \
		  exit 1; }
	@echo "Building Diktilo (Release, Developer ID signed, hardened runtime)..."
	@rm -rf "$(DIST_DERIVED_DATA)" "$(DIST_DIR)"
	@mkdir -p "$(DIST_DIR)"
	$(eval BUILD_NUMBER := $(shell git rev-list --count HEAD))
	$(eval MARKETING_VERSION := $(shell xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -showBuildSettings 2>/dev/null | awk -F ' = ' '/ MARKETING_VERSION /{print $$2; exit}'))
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
		-derivedDataPath "$(DIST_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="$(DEVELOPER_ID_IDENTITY)" \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGNING_REQUIRED=YES \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM_ID)" \
		PROVISIONING_PROFILE_SPECIFIER="" \
		ENABLE_HARDENED_RUNTIME=YES \
		OTHER_CODE_SIGN_FLAGS="--timestamp" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		build
	@APP_PATH="$(DIST_DERIVED_DATA)/Build/Products/Release/Diktilo.app" && \
	if [ ! -d "$$APP_PATH" ]; then echo "Error: Could not find built Diktilo.app at $$APP_PATH"; exit 1; fi && \
	echo "Re-signing vendored frameworks (Xcode signs these ad-hoc regardless of" && \
	echo "CODE_SIGN_IDENTITY — known Sparkle/SPM-package notarization gotcha)..." && \
	FW="$$APP_PATH/Contents/Frameworks" && \
	codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
		--sign "$(DEVELOPER_ID_IDENTITY)" "$$FW/Sparkle.framework/Versions/B/Autoupdate" && \
	codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
		--sign "$(DEVELOPER_ID_IDENTITY)" "$$FW/Sparkle.framework/Versions/B/Updater.app" && \
	codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
		--sign "$(DEVELOPER_ID_IDENTITY)" "$$FW/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" && \
	codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
		--sign "$(DEVELOPER_ID_IDENTITY)" "$$FW/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" && \
	codesign --force --options runtime --timestamp \
		--sign "$(DEVELOPER_ID_IDENTITY)" "$$FW/Sparkle.framework" && \
	codesign --force --options runtime --timestamp \
		--sign "$(DEVELOPER_ID_IDENTITY)" "$$FW/whisper.framework" && \
	codesign --force --options runtime --timestamp \
		--sign "$(DEVELOPER_ID_IDENTITY)" "$$FW/MediaRemoteAdapter.framework" && \
	echo "Re-signing main app bundle..." && \
	codesign --force --options runtime --timestamp \
		--entitlements "$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		--sign "$(DEVELOPER_ID_IDENTITY)" "$$APP_PATH" && \
	echo "Verifying code signature..." && \
	codesign --verify --deep --strict --verbose=2 "$$APP_PATH" && \
	STAGE="$(DIST_DIR)/stage" && mkdir -p "$$STAGE" && \
	ditto "$$APP_PATH" "$$STAGE/Diktilo.app" && \
	ln -s /Applications "$$STAGE/Applications" && \
	DMG_PATH="$(DIST_DIR)/Diktilo-$(MARKETING_VERSION)-$(BUILD_NUMBER).dmg" && \
	hdiutil create -volname Diktilo -srcfolder "$$STAGE" -ov -format UDZO "$$DMG_PATH" && \
	rm -rf "$$STAGE" && \
	codesign --sign "$(DEVELOPER_ID_IDENTITY)" --timestamp "$$DMG_PATH" && \
	echo "" && \
	echo "Built: $$DMG_PATH" && \
	echo "Run 'make notarize DMG=$$DMG_PATH' next (or just 'make notarize', picks up the newest dist/*.dmg)."

# Submit the most recent (or DMG=path) dist/*.dmg to Apple notarization,
# staple the ticket on success, and verify Gatekeeper accepts it.
# One-time setup on the signing Mac:
#   xcrun notarytool store-credentials diktilo-notary \
#     --apple-id <apple-id> --team-id $(DEVELOPMENT_TEAM_ID)
# (run directly in Terminal.app, NOT over a bare non-interactive ssh session —
# notarytool needs the login keychain unlocked, which a bare ssh session may
# not have; run `make notarize` the same way, interactively on the Mac.)
notarize:
	$(eval DMG := $(or $(DMG),$(shell ls -t "$(DIST_DIR)"/*.dmg 2>/dev/null | head -1)))
	@if [ -z "$(DMG)" ] || [ ! -f "$(DMG)" ]; then \
		echo "No dmg found. Run 'make dmg' first, or pass DMG=path/to/file.dmg"; exit 1; \
	fi
	@echo "Submitting $(DMG) for notarization (this can take a few minutes)..."
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@echo "Stapling ticket..."
	xcrun stapler staple "$(DMG)"
	@echo "Verifying Gatekeeper acceptance..."
	spctl -a -t open --context context:primary-signature -v "$(DMG)"
	@echo ""
	@echo "Ready to distribute: $(DMG)"

# Run application
run:
	@if [ -d "$$HOME/Downloads/VoiceInk.app" ]; then \
		echo "Opening ~/Downloads/VoiceInk.app..."; \
		open "$$HOME/Downloads/VoiceInk.app"; \
	else \
		echo "Looking for VoiceInk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "VoiceInk.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  dmg                Build a Developer ID-signed, hardened-runtime .dmg (dist/)"
	@echo "  notarize           Submit dist/*.dmg to Apple, staple ticket, verify Gatekeeper"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"