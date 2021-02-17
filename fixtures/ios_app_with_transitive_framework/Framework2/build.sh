#!/bin/sh

tuist generate

TEMP_DIR="/tmp/tuist-framework-2-fixture"
IPHONE_SIM_DIR="$TEMP_DIR/Build/Products/Debug-iphoneos"
IPHONE_OS_DIR="$TEMP_DIR/Build/Products/Debug-iphonesimulator"
mkdir -p $TEMP_DIR

xcrun xcodebuild build -scheme Framework2-iOS -workspace Framework2.xcworkspace -sdk iphoneos -destination "generic/platform=iOS" -derivedDataPath $TEMP_DIR
xcrun xcodebuild build -scheme Framework2-iOS -workspace Framework2.xcworkspace -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 11,OS=latest" -derivedDataPath $TEMP_DIR

mkdir -p prebuilt/Framework2.framework

lipo -create \
    "$IPHONE_OS_DIR/Framework2.framework/Framework2" \
    "$IPHONE_SIM_DIR/Framework2.framework/Framework2" \
    -output "$(pwd)/prebuilt/Framework2.framework/Framework2"

cp \
    "$IPHONE_OS_DIR/Framework2.framework/Info.plist" \
    "$(pwd)/prebuilt/Framework2.framework/Info.plist"

mkdir -p prebuilt/Framework2.framework/Headers
cp -r \
    "$IPHONE_OS_DIR/Framework2.framework/Headers/"* \
    "$(pwd)/prebuilt/Framework2.framework/Headers/"

mkdir -p prebuilt/Framework2.framework/Modules
cp \
    "$IPHONE_OS_DIR/Framework2.framework/Modules/module.modulemap" \
    "$(pwd)/prebuilt/Framework2.framework/Modules/module.modulemap"

mkdir -p prebuilt/Framework2.framework/Modules/Framework2.swiftmodule
cp -r \
    "$IPHONE_OS_DIR/Framework2.framework/Modules/Framework2.swiftmodule/"* \
    "$IPHONE_SIM_DIR/Framework2.framework/Modules/Framework2.swiftmodule/"* \
    "$(pwd)/prebuilt/Framework2.framework/Modules/Framework2.swiftmodule/"