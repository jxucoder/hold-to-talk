.PHONY: build run clean notarize

SIGNING_IDENTITY ?= -

build:
	swift build -c release
	@mkdir -p .build/PushieTalkie.app/Contents/MacOS
	@mkdir -p .build/PushieTalkie.app/Contents/Resources
	@cp .build/release/PushieTalkie .build/PushieTalkie.app/Contents/MacOS/
	@cp Resources/Info.plist .build/PushieTalkie.app/Contents/
	@cp Resources/PushieTalkie.icns .build/PushieTalkie.app/Contents/Resources/
	@if [ "$(SIGNING_IDENTITY)" = "-" ]; then \
		codesign -f -s - --entitlements Resources/PushieTalkie.entitlements .build/PushieTalkie.app; \
	else \
		codesign -f --options runtime --timestamp -s "$(SIGNING_IDENTITY)" --entitlements Resources/PushieTalkie.entitlements .build/PushieTalkie.app; \
	fi
	@echo "Built .build/PushieTalkie.app"

notarize:
	@test "$(SIGNING_IDENTITY)" != "-" || (echo "Error: set SIGNING_IDENTITY to your Developer ID Application certificate" && exit 1)
	@test -n "$(APPLE_ID)" || (echo "Error: set APPLE_ID to your Apple ID email" && exit 1)
	@test -n "$(APPLE_TEAM_ID)" || (echo "Error: set APPLE_TEAM_ID to your Apple Developer Team ID" && exit 1)
	cd .build && zip -r PushieTalkie.zip PushieTalkie.app
	xcrun notarytool submit .build/PushieTalkie.zip \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--wait
	xcrun stapler staple .build/PushieTalkie.app
	@rm .build/PushieTalkie.zip
	@echo "Notarization complete — .build/PushieTalkie.app is ready for distribution"

run: build
	open .build/PushieTalkie.app

clean:
	swift package clean
	rm -rf .build/PushieTalkie.app
