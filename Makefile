package-release:
	mkdir -p build
	swift build --product tuist --configuration release;
	swift build --product ProjectDescription --configuration release;
	cd .build/release && zip -q -r --symlinks tuist.zip tuist ProjectDescription.swiftmodule ProjectDescription.swiftdoc libProjectDescription.dylib
	cp -f .build/release/tuist.zip build/tuist.zip
	swift build --product tuistenv --configuration release;
	cd .build/release && zip -q -r --symlinks tuistenv.zip tuistenv
	cp -rf .build/release/tuistenv.zip build/tuistenv.zip