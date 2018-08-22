build-env:
	swift build --product tuistenv --static-swift-stdlib --configuration release;
	cp -rf .build/release/tuistenv bin/tuistenv;
	shasum -a 256 bin/tuistenv;
sha256:
	shasum -a 256 bin/tuistenv;
zip-release:
	swift build --product tuist --static-swift-stdlib --configuration release;
	swift build --product ProjectDescription --static-swift-stdlib --configuration release;
	cd .build/release && zip -q -r --symlinks tuist.zip tuist ProjectDescription.swiftmodule ProjectDescription.swiftdoc libProjectDescription.dylib
	cp -f .build/release/tuist.zip tuist.zip