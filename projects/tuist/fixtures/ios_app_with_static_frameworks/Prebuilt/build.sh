#!/bin/sh

swift run tuist generate

WORKSPACE_NAME="Prebuilt"
FRAMEWORK_NAME="PrebuiltStaticFramework"
TEMP_DIR="/tmp/tuist-$FRAMEWORK_NAME-fixture"
IPHONE_SIM_DIR="$TEMP_DIR/Build/Products/Debug-iphoneos"
IPHONE_OS_DIR="$TEMP_DIR/Build/Products/Debug-iphonesimulator"

mkdir -p $TEMP_DIR

xcrun xcodebuild build -scheme "$FRAMEWORK_NAME" -workspace "$WORKSPACE_NAME.xcworkspace" -sdk iphoneos -destination "generic/platform=iOS" -derivedDataPath $TEMP_DIR
xcrun xcodebuild build -scheme "$FRAMEWORK_NAME" -workspace "$WORKSPACE_NAME.xcworkspace" -sdk iphonesimulator -destination "platform=iOS Simulator,name=iPhone 11,OS=latest" -derivedDataPath $TEMP_DIR

mkdir -p "prebuilt/$FRAMEWORK_NAME.framework"

lipo -create \
    "$IPHONE_OS_DIR/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" \
    "$IPHONE_SIM_DIR/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" \
    -output "$(pwd)/prebuilt/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"

cp \
    "$IPHONE_OS_DIR/$FRAMEWORK_NAME.framework/Info.plist" \
    "$(pwd)/prebuilt/$FRAMEWORK_NAME.framework/Info.plist"

mkdir -p "prebuilt/$FRAMEWORK_NAME.framework/Headers"
cp -r \
    "$IPHONE_OS_DIR/$FRAMEWORK_NAME.framework/Headers/"* \
    "$(pwd)/prebuilt/$FRAMEWORK_NAME.framework/Headers/"

mkdir -p "prebuilt/$FRAMEWORK_NAME.framework/Modules"
cp \
    "$IPHONE_OS_DIR/$FRAMEWORK_NAME.framework/Modules/module.modulemap" \
    "$(pwd)/prebuilt/$FRAMEWORK_NAME.framework/Modules/module.modulemap"

mkdir -p "prebuilt/$FRAMEWORK_NAME.framework/Modules/$FRAMEWORK_NAME.swiftmodule"
cp -r \
    "$IPHONE_OS_DIR/$FRAMEWORK_NAME.framework/Modules/$FRAMEWORK_NAME.swiftmodule/"* \
    "$IPHONE_SIM_DIR/$FRAMEWORK_NAME.framework/Modules/$FRAMEWORK_NAME.swiftmodule/"* \
    "$(pwd)/prebuilt/$FRAMEWORK_NAME.framework/Modules/$FRAMEWORK_NAME.swiftmodule/"
