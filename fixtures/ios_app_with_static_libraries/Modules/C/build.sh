#!/bin/sh

swift run tuist generate

TEMP_DIR="/tmp/tuist-lib-c-fixture"
IPHONE_SIM_DIR="$TEMP_DIR/Build/Products/Debug-iphoneos"
IPHONE_OS_DIR="$TEMP_DIR/Build/Products/Debug-iphonesimulator"
mkdir -p $TEMP_DIR

xcrun xcodebuild build -scheme C -workspace C.xcworkspace -sdk iphoneos -destination "generic/platform=iOS" -derivedDataPath $TEMP_DIR
xcrun xcodebuild build -scheme C -workspace C.xcworkspace -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 11,OS=latest" -derivedDataPath $TEMP_DIR

mkdir -p prebuilt
lipo -create \
    "$IPHONE_OS_DIR/libC.a" \
    "$IPHONE_SIM_DIR/libC.a" \
    -output "$(pwd)/prebuilt/C/libC.a"

mkdir -p prebuilt/C/C.swiftmodule
cp -r \
    "$IPHONE_OS_DIR/C.swiftmodule/"* \
    "$IPHONE_SIM_DIR/C.swiftmodule/"* \
    "$(pwd)/prebuilt/C/C.swiftmodule/"

