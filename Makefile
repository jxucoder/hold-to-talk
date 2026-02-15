.PHONY: build run clean

build:
	swift build -c release
	@mkdir -p .build/OpenMumble.app/Contents/MacOS
	@mkdir -p .build/OpenMumble.app/Contents/Resources
	@cp .build/release/OpenMumble .build/OpenMumble.app/Contents/MacOS/
	@cp Resources/Info.plist .build/OpenMumble.app/Contents/
	@echo "Built .build/OpenMumble.app"

run: build
	open .build/OpenMumble.app

clean:
	swift package clean
	rm -rf .build/OpenMumble.app
