.PHONY: build install verify package package-zip package-dmg \
 notarize notarize-app notarize-dmg release permissions-reset reset-fresh-test run clean

APP_NAME := HoldToTalk
APP_BUNDLE := .build/$(APP_NAME).app
APP_INSTALL_DIR ?= /Applications
SIGNING_IDENTITY ?= -
DIST_DIR ?= dist
DMG_VOLUME_NAME ?= Hold to Talk

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUNDLE_ID := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)
ZIP_NAME ?= $(APP_NAME)-v$(VERSION).zip
DMG_NAME ?= $(APP_NAME)-v$(VERSION).dmg
ZIP_PATH := $(DIST_DIR)/$(ZIP_NAME)
DMG_PATH := $(DIST_DIR)/$(DMG_NAME)
DMG_STAGING := .build/dmg-staging
NOTARY_TMP_ZIP := .build/$(APP_NAME)-notary.zip

SPARKLE_FRAMEWORK := $(shell swift build -c release --show-bin-path)/Sparkle.framework

build:
	swift build -c release
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@mkdir -p "$(APP_BUNDLE)/Contents/Frameworks"
	@cp ".build/release/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/"
	@cp Resources/HoldToTalk.icns "$(APP_BUNDLE)/Contents/Resources/"
	@cp Resources/PrivacyInfo.xcprivacy "$(APP_BUNDLE)/Contents/Resources/"
	@rsync -a --delete "$(SPARKLE_FRAMEWORK)" "$(APP_BUNDLE)/Contents/Frameworks/"
	@install_name_tool -add_rpath @executable_path/../Frameworks "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@if [ "$(SIGNING_IDENTITY)" = "-" ]; then \
		codesign -f --deep -s - "$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework"; \
		codesign -f -s - --entitlements Resources/HoldToTalk.dev.entitlements "$(APP_BUNDLE)"; \
	else \
		codesign -f --deep --options runtime --timestamp -s "$(SIGNING_IDENTITY)" "$(APP_BUNDLE)/Contents/Frameworks/Sparkle.framework"; \
		codesign -f --options runtime --timestamp -s "$(SIGNING_IDENTITY)" --entitlements Resources/HoldToTalk.direct.entitlements "$(APP_BUNDLE)"; \
	fi
	@echo "Built $(APP_BUNDLE)"

install: build
	@mkdir -p "$(APP_INSTALL_DIR)"
	@rm -rf "$(APP_INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(APP_INSTALL_DIR)/"
	@xattr -dr com.apple.quarantine "$(APP_INSTALL_DIR)/$(APP_NAME).app" 2>/dev/null || true
	@echo "Installed to $(APP_INSTALL_DIR)/$(APP_NAME).app"

verify: build
	@codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"
	@spctl -a -t exec -vv "$(APP_BUNDLE)" || true

package: package-zip package-dmg

package-zip: build
	@mkdir -p "$(DIST_DIR)"
	@ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(ZIP_PATH)"
	@echo "Packaged $(ZIP_PATH)"

package-dmg: build
	@mkdir -p "$(DIST_DIR)"
	@bash scripts/package-dmg.sh \
		--app-bundle "$(APP_BUNDLE)" \
		--volume-name "$(DMG_VOLUME_NAME)" \
		--output "$(DMG_PATH)"

notarize: notarize-app

notarize-app: build _check-signing _check-notary
	@ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(NOTARY_TMP_ZIP)"
	@xcrun notarytool submit "$(NOTARY_TMP_ZIP)" \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--wait
	@xcrun stapler staple "$(APP_BUNDLE)"
	@rm -f "$(NOTARY_TMP_ZIP)"
	@echo "Notarized and stapled $(APP_BUNDLE)"

notarize-dmg: package-dmg _check-signing _check-notary
	@xcrun notarytool submit "$(DMG_PATH)" \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--wait
	@xcrun stapler staple "$(DMG_PATH)"
	@echo "Notarized and stapled $(DMG_PATH)"

release: notarize-app package-zip package-dmg notarize-dmg
	@echo "Release artifacts:"
	@echo "  - $(ZIP_PATH)"
	@echo "  - $(DMG_PATH)"

permissions-reset:
	@echo "Resetting TCC permissions for $(BUNDLE_ID)"
	@tccutil reset Microphone "$(BUNDLE_ID)" || true
	@tccutil reset Accessibility "$(BUNDLE_ID)" || true
	@tccutil reset ListenEvent "$(BUNDLE_ID)" || true
	@echo "Done. Launch app from /Applications to re-run onboarding prompts."

reset-fresh-test:
	@APP_USER="$(APP_USER)" bash scripts/reset-fresh-test.sh $(ARGS)

run: build
	open "$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)" "$(DIST_DIR)" "$(DMG_STAGING)" "$(NOTARY_TMP_ZIP)"

_check-signing:
	@test "$(SIGNING_IDENTITY)" != "-" || (echo "Error: set SIGNING_IDENTITY to your Developer ID Application certificate" && exit 1)

_check-notary:
	@test -n "$(APPLE_ID)" || (echo "Error: set APPLE_ID to your Apple ID email" && exit 1)
	@test -n "$(APPLE_TEAM_ID)" || (echo "Error: set APPLE_TEAM_ID to your Apple Developer Team ID" && exit 1)
	@test -n "$(APPLE_APP_PASSWORD)" || (echo "Error: set APPLE_APP_PASSWORD to your app-specific password" && exit 1)
