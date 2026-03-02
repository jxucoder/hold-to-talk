.PHONY: build run clean notarize

SIGNING_IDENTITY ?= -

build:
	swift build -c release
	@mkdir -p .build/HoldToTalk.app/Contents/MacOS
	@mkdir -p .build/HoldToTalk.app/Contents/Resources
	@cp .build/release/HoldToTalk .build/HoldToTalk.app/Contents/MacOS/
	@cp Resources/Info.plist .build/HoldToTalk.app/Contents/
	@cp Resources/HoldToTalk.icns .build/HoldToTalk.app/Contents/Resources/
	@if [ "$(SIGNING_IDENTITY)" = "-" ]; then \
		codesign -f -s - --entitlements Resources/HoldToTalk.dev.entitlements .build/HoldToTalk.app; \
	else \
		codesign -f --options runtime --timestamp -s "$(SIGNING_IDENTITY)" --entitlements Resources/HoldToTalk.entitlements .build/HoldToTalk.app; \
	fi
	@echo "Built .build/HoldToTalk.app"

notarize:
	@test "$(SIGNING_IDENTITY)" != "-" || (echo "Error: set SIGNING_IDENTITY to your Developer ID Application certificate" && exit 1)
	@test -n "$(APPLE_ID)" || (echo "Error: set APPLE_ID to your Apple ID email" && exit 1)
	@test -n "$(APPLE_TEAM_ID)" || (echo "Error: set APPLE_TEAM_ID to your Apple Developer Team ID" && exit 1)
	cd .build && zip -r HoldToTalk.zip HoldToTalk.app
	xcrun notarytool submit .build/HoldToTalk.zip \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--wait
	xcrun stapler staple .build/HoldToTalk.app
	@rm .build/HoldToTalk.zip
	@echo "Notarization complete — .build/HoldToTalk.app is ready for distribution"

run: build
	open .build/HoldToTalk.app

clean:
	swift package clean
	rm -rf .build/HoldToTalk.app
