#!/usr/bin/env bash
#MISE description="Builds a relocatable macOS CLI preview distribution"
#USAGE arg "<output>" help="A new directory for the distribution"

set -euo pipefail

ROOT="${MISE_PROJECT_ROOT:?Run through mise run cli:preview}"
OUTPUT="${usage_output:?Specify a new output directory}"
if [ -e "$OUTPUT" ]; then
    echo "Output already exists: $OUTPUT" >&2
    exit 1
fi
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
DERIVED_DATA="$STAGING/derived-data"
DIST="$STAGING/distribution"
mkdir -p "$DIST"

TUIST_FORCE_STATIC_LINKING=1 tuist generate tuist ProjectDescription --no-open --no-binary-cache
for scheme in tuist ProjectDescription; do
    DISTRIBUTION=NO
    if [ "$scheme" = ProjectDescription ]; then
        tuist generate ProjectDescription --no-open --no-binary-cache
        DISTRIBUTION=YES
    fi
    xcodebuild build -workspace "$ROOT/Tuist.xcworkspace" -scheme "$scheme" \
        -derivedDataPath "$DERIVED_DATA" -configuration Release -destination platform=macOS \
        ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES BUILD_LIBRARY_FOR_DISTRIBUTION="$DISTRIBUTION" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
done

PRODUCTS="$DERIVED_DATA/Build/Products/Release"
cp "$PRODUCTS/tuist" "$DIST/tuist"
cp -R "$PRODUCTS/ProjectDescription.framework" "$DIST/"
cp -R "$ROOT/cli/Templates" "$DIST/"
find "$PRODUCTS" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$DIST/" \;

(
    # Resolve the crate's pinned Rust toolchain, as the release bundler does.
    cd "$ROOT/cas-plugin"
    CARGO_TARGET_DIR="$STAGING/rust" mise exec -- cargo build --release --lib --bin tuist-cas-proxy
)
cp "$STAGING/rust/release/libtuist_cas_plugin.dylib" "$DIST/"
cp "$STAGING/rust/release/tuist-cas-proxy" "$DIST/"
install_name_tool -id libtuist_cas_plugin.dylib "$DIST/libtuist_cas_plugin.dylib"

mkdir -p "$DIST/vendor"
xcrun swift-stdlib-tool --copy --scan-executable "$DIST/tuist" \
    --scan-executable "$DIST/ProjectDescription.framework/ProjectDescription" \
    --platform macosx --destination "$DIST/vendor"
if find "$DIST/vendor" -name '*.dylib' -print -quit | grep -q .; then
    install_name_tool -add_rpath '@executable_path/vendor' "$DIST/tuist"
    install_name_tool -add_rpath '@loader_path/../../../vendor' "$DIST/ProjectDescription.framework/ProjectDescription"
fi

# PR builds are ad-hoc signed, not Developer ID signed or notarized releases.
find "$DIST/vendor" -name '*.dylib' -exec codesign --force --sign - {} \;
for binary in libtuist_cas_plugin.dylib tuist-cas-proxy tuist ProjectDescription.framework; do
    codesign --force --sign - "$DIST/$binary"
done

mkdir -p "$(dirname "$OUTPUT")"
mv "$DIST" "$OUTPUT"
echo "Preview distribution: $OUTPUT"
