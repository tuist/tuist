#!/bin/bash

FRAMEWORK_NAME="MyStaticFramework"
TEMP_PATH=$(mktemp -d)
DERIVED_DATA_PATH="$TEMP_PATH/DerivedData"
XCARCHIVE_PATH="$TEMP_PATH/Archives"


xcrun xcodebuild \
    archive \
    -scheme "$FRAMEWORK_NAME" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -archivePath "$XCARCHIVE_PATH/$FRAMEWORK_NAME-ios.xcarchive" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    SKIP_INSTALL=NO

xcrun xcodebuild \
    archive \
    -scheme "$FRAMEWORK_NAME" \
    -sdk iphonesimulator \
    -destination="iOS Simulator" \
    -archivePath "$XCARCHIVE_PATH/$FRAMEWORK_NAME-ios-simulator.xcarchive" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    SKIP_INSTALL=NO

xcrun xcodebuild \
    -create-xcframework \
    -framework "$XCARCHIVE_PATH/$FRAMEWORK_NAME-ios.xcarchive/Products/Library/Frameworks/$FRAMEWORK_NAME.framework" \
    -framework "$XCARCHIVE_PATH/$FRAMEWORK_NAME-ios-simulator.xcarchive/Products/Library/Frameworks/$FRAMEWORK_NAME.framework" \
    -output "$(pwd)/prebuilt/$FRAMEWORK_NAME.xcframework"
