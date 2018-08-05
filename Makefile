build-env:
	swift build --product tuistenv --static-swift-stdlib --configuration release;
	cp -rf .build/release/tuistenv bin/tuistenv;
  shasum -a 256 bin/tuistenv;
sha256:
	shasum -a 256 bin/tuistenv;