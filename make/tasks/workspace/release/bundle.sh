#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../../utilities/root_dir.sh)
source $ROOT_DIR/make/utilities/setup.sh
XCODE_PATH_SCRIPT_PATH=$SCRIPT_DIR/../../../utilities/xcode_path.sh
BUILD_DIRECTORY=$ROOT_DIR/build
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT # Ensures it gets deleted
XCODE_VERSION=$(cat $ROOT_DIR/.xcode-version)
LIBRARIES_XCODE_VERSION=$(cat $ROOT_DIR/.xcode-version-libraries)
BUILD_DIR=$ROOT_DIR/build

echo "$(format_section "Building release into $BUILD_DIRECTORY")"

XCODE_PATH=$($XCODE_PATH_SCRIPT_PATH --version $XCODE_VERSION)
XCODE_LIBRARIES_PATH=$($XCODE_PATH_SCRIPT_PATH --version $LIBRARIES_XCODE_VERSION)

echo "Static executables will be built with $XCODE_PATH"
echo "Dynamic bundles will be built with $XCODE_PATH"

rm -rf $ROOT_DIR/Tuist.xcodeproj
rm -rf $ROOT_DIR/Tuist.xcworkspace
rm -rf $BUILD_DIRECTORY
mkdir -p $BUILD_DIRECTORY

build_fat_release_library() {
    (
    cd $ROOT_DIR || exit 1
    DEVELOPER_DIR=$XCODE_LIBRARIES_PATH xcrun xcodebuild -resolvePackageDependencies
    DEVELOPER_DIR=$XCODE_LIBRARIES_PATH xcrun xcodebuild -scheme $1 -configuration Release -destination platform=macosx BUILD_LIBRARY_FOR_DISTRIBUTION=YES ARCHS='arm64 x86_64' BUILD_DIR=$TMP_DIR clean build

    # We remove the PRODUCT.swiftmodule/Project directory because
    # this directory contains objects that are not stable across Swift releases.
    rm -rf $TMP_DIR/Release/$1.swiftmodule/Project
    cp -r $TMP_DIR/Release/PackageFrameworks/$1.framework $BUILD_DIRECTORY/$1.framework
    mkdir -p $BUILD_DIRECTORY/$1.framework/Modules
    cp -r $TMP_DIR/Release/$1.swiftmodule $BUILD_DIRECTORY/$1.framework/Modules/$1.swiftmodule
    cp -r $TMP_DIR/Release/$1.framework.dSYM $BUILD_DIRECTORY/$1.framework.dSYM
    )
}

build_fat_release_binary() {
    (
    cd $ROOT_DIR || exit 1
    ARM64_TARGET=arm64-apple-macosx 
    X86_64_TARGET=x86_64-apple-macosx

    swift build \
        --configuration release \
        --disable-sandbox \
        --product $1 \
        --build-path $TMP_DIR \
        --triple $ARM64_TARGET \
        --triple $X86_64_TARGET

    lipo -create \
        -output $BUILD_DIRECTORY/$1 \
        $TMP_DIR/$ARM64_TARGET/release/$1 \
        $TMP_DIR/$X86_64_TARGET/release/$1
    )
}

echo "$(format_subsection "Building ProjectDescription")"
build_fat_release_library "ProjectDescription"

echo "$(format_subsection "Tuist")"
build_fat_release_binary "tuist"

# TODO
# Copy the vendor directory
# Copy the template directory
# Run stdlib-tool tool
# Compress
# Generate checksums
