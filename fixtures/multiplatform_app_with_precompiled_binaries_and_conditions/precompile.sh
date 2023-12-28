#!/usr/bin/env bash

DIR="$(dirname "$0")"
TMP_DIR=$(mktemp -d)

trap cleanup EXIT

cleanup() {
  echo "Removing temporary directory."
  rm -rf "$TMP_DIR"
}

tuist generate --path $DIR --no-open

ios_destinations=$(xcodebuild -showdestinations -workspace "$DIR/App.xcworkspace" -scheme iOSDynamicFramework)
ios_simulator_id=$(echo "$ios_destinations" | 
               grep 'platform:iOS Simulator' | 
               grep -v 'Any iOS Simulator Device' | 
               awk -F ', ' '{print $2}' | 
               awk -F ':' '{print $2}' | 
               head -n 1)
watchos_destinations=$(xcodebuild -showdestinations -workspace "$DIR/App.xcworkspace" -scheme watchOSStaticLibrary)
watchos_simulator_id=$(echo "$watchos_destinations" | 
               grep 'platform:watchOS Simulator' | 
               grep -v 'Any watchOS Simulator Device' | 
               awk -F ', ' '{print $2}' | 
               awk -F ':' '{print $2}' | 
               head -n 1)

xcodebuild \
    -workspace "$DIR/App.xcworkspace" \
    -scheme iOSDynamicFramework \
    -configuration Debug \
    -derivedDataPath "$TMP_DIR" \
    -destination "id=$ios_simulator_id" \
    -destination 'generic/platform=iOS'

xcodebuild \
    -workspace "$DIR/App.xcworkspace" \
    -scheme watchOSStaticLibrary \
    -configuration Debug \
    -derivedDataPath "$TMP_DIR" \
    -destination "id=$watchos_simulator_id" \
    -destination 'generic/platform=watchOS'

mkdir -p $DIR/Precompiled/iphoneos/
cp -Rf $TMP_DIR/Build/Products/Debug-iphoneos/iOSDynamicFramework.framework $DIR/Precompiled/iphoneos/iOSDynamicFramework.framework
mkdir -p $DIR/Precompiled/iphonesimulator/
cp -Rf $TMP_DIR/Build/Products/Debug-iphonesimulator/iOSDynamicFramework.framework $DIR/Precompiled/iphonesimulator/iOSDynamicFramework.framework
mkdir -p $DIR/Precompiled/watchos/
cp -Rf $TMP_DIR/Build/Products/Debug-watchos/libwatchOSStaticLibrary.a $DIR/Precompiled/watchos/libwatchOSStaticLibrary.a
cp -Rf $TMP_DIR/Build/Products/Debug-watchos/watchOSStaticLibrary.swiftmodule $DIR/Precompiled/watchos/watchOSStaticLibrary.swiftmodule
mkdir -p $DIR/Precompiled/watchsimulator/
cp -Rf $TMP_DIR/Build/Products/Debug-watchsimulator/libwatchOSStaticLibrary.a $DIR/Precompiled/watchsimulator/libwatchOSStaticLibrary.a
cp -Rf $TMP_DIR/Build/Products/Debug-watchsimulator/watchOSStaticLibrary.swiftmodule $DIR/Precompiled/watchsimulator/watchOSStaticLibrary.swiftmodule
