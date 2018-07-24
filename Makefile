build-env:
	swift build --product tuistenv --static-swift-stdlib --configuration release;
	cp -rf .build/release/tuistenv bin/tuistenv