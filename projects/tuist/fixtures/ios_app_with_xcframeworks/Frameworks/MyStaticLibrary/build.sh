#!/bin/bash

rm -rf prebuilt
tuist generate --no-open

LIBRARY_NAME="MyStaticLibrary"
TEMP_PATH=$(mktemp -d)
DERIVED_DATA_PATH="$TEMP_PATH/DerivedData"
XCARCHIVE_PATH="$TEMP_PATH/Archives"

xcrun xcodebuild \
    archive \
    -scheme "$LIBRARY_NAME" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -archivePath "$XCARCHIVE_PATH/$LIBRARY_NAME-ios.xcarchive" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    SKIP_INSTALL=NO
    ONLY_ACTIVE_ARCH=NO

xcrun xcodebuild \
    archive \
    -scheme "$LIBRARY_NAME" \
    -sdk iphonesimulator \
    -destination="iOS Simulator" \
    -archivePath "$XCARCHIVE_PATH/$LIBRARY_NAME-ios-simulator.xcarchive" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    SKIP_INSTALL=NO
    ONLY_ACTIVE_ARCH=NO

xcrun xcodebuild \
    -create-xcframework \
    -library "$XCARCHIVE_PATH/$LIBRARY_NAME-ios.xcarchive/Products/usr/local/lib/lib$LIBRARY_NAME.a" \
    -library "$XCARCHIVE_PATH/$LIBRARY_NAME-ios-simulator.xcarchive/Products/usr/local/lib/lib$LIBRARY_NAME.a" \
    -output "$(pwd)/prebuilt/$LIBRARY_NAME.xcframework"
