#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../../utilities/root_dir.sh)
source $ROOT_DIR/make/utilities/setup.sh
XCODE_PATH_SCRIPT_PATH=$SCRIPT_DIR/../../../utilities/xcode_path.sh
BUILD_DIRECTORY=$ROOT_DIR/build
# Xcode 15 has a bug that causes the /var/folders... temporary directory, which is a symlink to
# /private/var/folders to crash Xcode.
TMP_DIR=/private$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT # Ensures it gets deleted
XCODE_VERSION=$(cat $ROOT_DIR/.xcode-version)
LIBRARIES_XCODE_VERSION=$(cat $ROOT_DIR/.xcode-version-libraries)
BUILD_DIR=$ROOT_DIR/build

echo "$(format_section "Building release into $BUILD_DIRECTORY")"

XCODE_PATH=/Applications/Xcode_15.0.app
# TODO:
# Remove the hardcoded path. The GitHub hosted runners have the dev tools of 15.0.1
# and causes the line below to output a non-existing path. Once they've installed 15.0.1
# in the CI environments, the hardcoded path should not be necessary.
# That will happen when this PR is merged and deployed: https://github.com/actions/runner-images/pull/8601
# XCODE_PATH=$($XCODE_PATH_SCRIPT_PATH --version $XCODE_VERSION)
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

build_xcframework_library() {
    (
    cd $ROOT_DIR || exit 1
    DEVELOPER_DIR=$XCODE_LIBRARIES_PATH xcrun xcodebuild -resolvePackageDependencies
    DEVELOPER_DIR=$XCODE_LIBRARIES_PATH xcrun xcodebuild -scheme $1 -configuration Release -destination platform=macosx BUILD_LIBRARY_FOR_DISTRIBUTION=YES ARCHS='arm64 x86_64' BUILD_DIR=$TMP_DIR clean build
    
    xcodebuild -create-xcframework \
           -framework $TMP_DIR/Release/PackageFrameworks/$1.framework \
           -output $BUILD_DIRECTORY/$1.xcframework    
    cp -r $TMP_DIR/Release/$1.framework.dSYM $BUILD_DIRECTORY/$1.xcframework.dSYM
    )
}

build_fat_release_binary() {
    (
    cd $ROOT_DIR || exit 1
    ARM64_TARGET=arm64-apple-macosx 
    X86_64_TARGET=x86_64-apple-macosx

   DEVELOPER_DIR=$XCODE_PATH swift build \
        --configuration release \
        --disable-sandbox \
        --product $1 \
        --package-path $2 \
        --build-path $TMP_DIR/$1 \
        --triple $ARM64_TARGET

    DEVELOPER_DIR=$XCODE_PATH swift build \
        --configuration release \
        --disable-sandbox \
        --product $1 \
        --package-path $2 \
        --build-path $TMP_DIR/$1 \
        --triple $X86_64_TARGET

    mkdir -p $3
    
    DEVELOPER_DIR=$XCODE_PATH lipo -create \
        -output $3/$1 \
        $TMP_DIR/$1/$ARM64_TARGET/release/$1 \
        $TMP_DIR/$1/$X86_64_TARGET/release/$1
    )
}

echo "$(format_section "Building")"

echo "$(format_subsection "Building ProjectDescription framework")"
build_fat_release_library "ProjectDescription"

echo "$(format_subsection "Building ProjectAutomation framework")"
build_xcframework_library "ProjectAutomation"

echo "$(format_subsection "Building xcbeautify executable")"
build_fat_release_binary "xcbeautify" $ROOT_DIR/projects/tuist/vendor $BUILD_DIRECTORY/vendor

echo "$(format_subsection "Building tuist executable")"
build_fat_release_binary "tuist" $ROOT_DIR $BUILD_DIRECTORY

echo "$(format_subsection "Building tuist executable")"
build_fat_release_binary "tuistenv" $ROOT_DIR $BUILD_DIRECTORY

echo "$(format_section "Copying assets")"

echo "$(format_subsection "Copying Tuist's templates")"
cp -r $ROOT_DIR/Templates $BUILD_DIRECTORY/Templates

echo "$(format_subsection "Copy Swift libraries into the Tuist binary")"
swift stdlib-tool --copy --scan-executable $BUILD_DIRECTORY/tuist --platform macosx --destination $BUILD_DIRECTORY

echo "$(format_section "Bundling")"

(
    cd $BUILD_DIRECTORY || exit 1
    echo "$(format_subsection "Bundling tuistenv.zip")"
    zip -q -r --symlinks tuistenv.zip tuistenv
    echo "$(format_subsection "Bundling tuist.zip")"
    zip -q -r --symlinks tuist.zip tuist libswift_Concurrency.dylib ProjectAutomation.xcframework ProjectAutomation.xcframework.dSYM ProjectDescription.framework ProjectDescription.framework.dSYM Templates vendor
    echo "$(format_subsection "Bundling ProjectDescription.framework.zip")"
    zip -q -r --symlinks ProjectDescription.framework.zip ProjectDescription.framework ProjectDescription.framework.dSYM
    echo "$(format_subsection "Bundling ProjectAutomation.xcframework.zip")"
    zip -q -r --symlinks ProjectAutomation.xcframework.zip ProjectAutomation.xcframework ProjectAutomation.xcframework.dSYM

    rm -rf tuist tuistenv ProjectAutomation.xcframework ProjectAutomation.xcframework.dSYM ProjectDescription.framework ProjectDescription.framework.dSYM Templates vendor

    : > SHASUMS256.txt
    : > SHASUMS512.txt

    for file in *; do
        if [ -f "$file" ]; then
            if [[ "$file" == "SHASUMS256.txt" || "$file" == "SHASUMS512.txt" ]]; then
                continue
            fi
            echo "$(shasum -a 256 "$file" | awk '{print $1}') ./$file" >> SHASUMS256.txt
            echo "$(shasum -a 512 "$file" | awk '{print $1}') ./$file" >> SHASUMS512.txt
        fi
    done
)
