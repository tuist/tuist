#!/bin/sh

rm -rf prebuild
tuist generate --no-open

TEMP_DIR="/tmp/tuist-framework-2-fixture"
IPHONE_SIM_DIR="$TEMP_DIR/Build/Products/Debug-iphonesimulator"
MAC_OS_DIR="$TEMP_DIR/Build/Products/Debug"

rm -rf $TEMP_DIR
mkdir -p $TEMP_DIR

xcrun xcodebuild build -scheme Framework2-iOS -workspace Framework2.xcworkspace -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 14 Pro,OS=latest" -derivedDataPath $TEMP_DIR ONLY_ACTIVE_ARCH=NO
xcrun xcodebuild build -scheme Framework2-macOS -workspace Framework2.xcworkspace -derivedDataPath $TEMP_DIR

mkdir -p prebuilt/iOS/Framework2.framework
lipo -create \
    "$IPHONE_SIM_DIR/Framework2.framework/Framework2" \
    -output "$(pwd)/prebuilt/iOS/Framework2.framework/Framework2"

cp \
    "$IPHONE_SIM_DIR/Framework2.framework/Info.plist" \
    "$(pwd)/prebuilt/iOS/Framework2.framework/Info.plist"

mkdir -p prebuilt/iOS/Framework2.framework/Headers
cp -r \
    "$IPHONE_SIM_DIR/Framework2.framework/Headers/"* \
    "$(pwd)/prebuilt/iOS/Framework2.framework/Headers/"

mkdir -p prebuilt/iOS/Framework2.framework/Modules
cp \
    "$IPHONE_SIM_DIR/Framework2.framework/Modules/module.modulemap" \
    "$(pwd)/prebuilt/iOS/Framework2.framework/Modules/module.modulemap"

mkdir -p prebuilt/iOS/Framework2.framework/Modules/Framework2.swiftmodule
cp -r \
    "$IPHONE_SIM_DIR/Framework2.framework/Modules/Framework2.swiftmodule/"* \
    "$(pwd)/prebuilt/iOS/Framework2.framework/Modules/Framework2.swiftmodule/"

mkdir -p prebuilt/Mac/Framework2.framework
cp \
    "$MAC_OS_DIR/Framework2.framework/Framework2" \
    "$(pwd)/prebuilt/Mac/Framework2.framework/Framework2"

cp \
    "$MAC_OS_DIR/Framework2.framework/Resources/Info.plist" \
    "$(pwd)/prebuilt/Mac/Framework2.framework/Info.plist"

mkdir -p prebuilt/Mac/Framework2.framework/Headers
cp -r \
    "$MAC_OS_DIR/Framework2.framework/Headers/"* \
    "$(pwd)/prebuilt/Mac/Framework2.framework/Headers/"

mkdir -p prebuilt/Mac/Framework2.framework/Modules
cp \
    "$MAC_OS_DIR/Framework2.framework/Modules/module.modulemap" \
    "$(pwd)/prebuilt/Mac/Framework2.framework/Modules/module.modulemap"

mkdir -p prebuilt/Mac/Framework2.framework/Modules/Framework2.swiftmodule
cp -r \
    "$MAC_OS_DIR/Framework2.framework/Modules/Framework2.swiftmodule/"* \
    "$(pwd)/prebuilt/Mac/Framework2.framework/Modules/Framework2.swiftmodule/"
