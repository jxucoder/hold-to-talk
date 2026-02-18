.PHONY: build run clean

SIGNING_IDENTITY ?= -

build:
	swift build -c release
	@mkdir -p .build/OpenMumble.app/Contents/MacOS
	@mkdir -p .build/OpenMumble.app/Contents/Resources
	@cp .build/release/OpenMumble .build/OpenMumble.app/Contents/MacOS/
	@cp Resources/Info.plist .build/OpenMumble.app/Contents/
	@cp Resources/OpenMumble.icns .build/OpenMumble.app/Contents/Resources/
	@codesign -f -s "$(SIGNING_IDENTITY)" --entitlements Resources/OpenMumble.entitlements .build/OpenMumble.app
	@echo "Built .build/OpenMumble.app"

run: build
	open .build/OpenMumble.app

clean:
	swift package clean
	rm -rf .build/OpenMumble.app
