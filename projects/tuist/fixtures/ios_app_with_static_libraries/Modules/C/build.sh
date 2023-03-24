#!/bin/sh

rm -rf prebuilt
tuist generate --no-open

TEMP_DIR="/tmp/tuist-lib-c-fixture"
IPHONE_SIM_DIR="$TEMP_DIR/Build/Products/Debug-iphonesimulator"

rm -rf $TEMP_DIR
mkdir -p $TEMP_DIR

xcrun xcodebuild build -scheme C -workspace C.xcworkspace -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 13 Pro,OS=latest" -derivedDataPath $TEMP_DIR ONLY_ACTIVE_ARCH=NO

mkdir -p prebuilt/C
lipo -create \
    "$IPHONE_SIM_DIR/libC.a" \
    -output "$(pwd)/prebuilt/C/libC.a"

mkdir -p prebuilt/C/C.swiftmodule
cp -r \
    "$IPHONE_SIM_DIR/C.swiftmodule/"* \
    "$(pwd)/prebuilt/C/C.swiftmodule/"

