package-release:
	mkdir -p build
	swift build --product tuist --static-swift-stdlib --configuration release;
	swift build --product ProjectDescription --static-swift-stdlib --configuration release;
	cd .build/release && zip -q -r --symlinks tuist.zip tuist ProjectDescription.swiftmodule ProjectDescription.swiftdoc libProjectDescription.dylib
	cp -f .build/release/tuist.zip build/tuist.zip
	swift build --product tuistenv --static-swift-stdlib --configuration release;
	cd .build/release && zip -q -r --symlinks tuistenv.zip tuistenv
	cp -rf .build/release/tuistenv.zip build/tuistenv.zip