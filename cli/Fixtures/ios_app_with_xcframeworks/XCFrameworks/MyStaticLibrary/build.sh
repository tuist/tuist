#!/bin/bash -e

rm -rf prebuilt
tuist generate --no-open

LIBRARY_NAME="MyStaticLibrary"
TEMP_PATH=$(mktemp -d)
DERIVED_DATA_PATH="$TEMP_PATH/DerivedData"

xcrun xcodebuild \
    -scheme "$LIBRARY_NAME" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -config Release \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcrun xcodebuild \
    -scheme "$LIBRARY_NAME" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=iPhone 13 Pro,OS=latest" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -config Release \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

xcrun xcodebuild \
    -create-xcframework \
    -library "$DERIVED_DATA_PATH/Build/Products/Release-iphonesimulator/lib$LIBRARY_NAME.a" \
    -library "$DERIVED_DATA_PATH/Build/Products/Release-iphoneos/lib$LIBRARY_NAME.a" \
    -output "$(pwd)/prebuilt/$LIBRARY_NAME.xcframework"
