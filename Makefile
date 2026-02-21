.PHONY: build run clean notarize

SIGNING_IDENTITY ?= -

build:
	swift build -c release
	@mkdir -p .build/OpenMumble.app/Contents/MacOS
	@mkdir -p .build/OpenMumble.app/Contents/Resources
	@cp .build/release/OpenMumble .build/OpenMumble.app/Contents/MacOS/
	@cp Resources/Info.plist .build/OpenMumble.app/Contents/
	@cp Resources/OpenMumble.icns .build/OpenMumble.app/Contents/Resources/
	@if [ "$(SIGNING_IDENTITY)" = "-" ]; then \
		codesign -f -s - --entitlements Resources/OpenMumble.entitlements .build/OpenMumble.app; \
	else \
		codesign -f --options runtime --timestamp -s "$(SIGNING_IDENTITY)" --entitlements Resources/OpenMumble.entitlements .build/OpenMumble.app; \
	fi
	@echo "Built .build/OpenMumble.app"

notarize:
	@test "$(SIGNING_IDENTITY)" != "-" || (echo "Error: set SIGNING_IDENTITY to your Developer ID Application certificate" && exit 1)
	@test -n "$(APPLE_ID)" || (echo "Error: set APPLE_ID to your Apple ID email" && exit 1)
	@test -n "$(APPLE_TEAM_ID)" || (echo "Error: set APPLE_TEAM_ID to your Apple Developer Team ID" && exit 1)
	cd .build && zip -r OpenMumble.zip OpenMumble.app
	xcrun notarytool submit .build/OpenMumble.zip \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--wait
	xcrun stapler staple .build/OpenMumble.app
	@rm .build/OpenMumble.zip
	@echo "Notarization complete — .build/OpenMumble.app is ready for distribution"

run: build
	open .build/OpenMumble.app

clean:
	swift package clean
	rm -rf .build/OpenMumble.app
