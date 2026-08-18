.PHONY: generate build run install clean

generate:
	xcodegen generate

build: generate
	xcodebuild -scheme RecShot -configuration Debug -derivedDataPath build -destination 'platform=macOS' build

run: build
	open build/Build/Products/Debug/RecShot.app

install: build
	ditto build/Build/Products/Debug/RecShot.app /Applications/RecShot.app
	@echo "Installed RecShot to /Applications/RecShot.app"

clean:
	rm -rf build RecShot.xcodeproj
