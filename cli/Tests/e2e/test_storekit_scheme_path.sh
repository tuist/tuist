#!/bin/bash
# E2E test: verifies that StoreKit configuration paths in generated .xcscheme
# files do not contain a spurious "../" prefix.
#
# The bug: Tuist computed StoreKit paths relative to the .xcworkspace bundle
# (a directory), producing "../App/Config/Products.storekit" instead of
# "App/Config/Products.storekit". Xcode resolves these paths relative to the
# directory *containing* the .xcworkspace, so the "../" breaks resolution.
#
# Usage:
#   ./test_storekit_scheme_path.sh [path-to-tuist-binary]
#
# If no binary is provided, uses `tuist` from PATH.

set -euo pipefail

TUIST_BIN="${1:-tuist}"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

echo "==> Creating fixture in $FIXTURE_DIR"

# -- Tuist.swift
cat > "$FIXTURE_DIR/Tuist.swift" <<'SWIFT'
import ProjectDescription
let tuist = Tuist(project: .tuist())
SWIFT

# -- Workspace.swift (StoreKit path set at workspace level)
cat > "$FIXTURE_DIR/Workspace.swift" <<'SWIFT'
import ProjectDescription

let workspace = Workspace(
    name: "Workspace",
    projects: ["App"],
    schemes: [
        .scheme(
            name: "Workspace-App",
            shared: true,
            buildAction: .buildAction(
                targets: [.project(path: "App", target: "App")]
            ),
            runAction: .runAction(
                executable: .project(path: "App", target: "App"),
                options: .options(
                    storeKitConfigurationPath: "App/Config/Products.storekit"
                )
            )
        ),
    ]
)
SWIFT

# -- App/Project.swift
mkdir -p "$FIXTURE_DIR/App/Sources" "$FIXTURE_DIR/App/Config"

cat > "$FIXTURE_DIR/App/Project.swift" <<'SWIFT'
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.storekit.test",
            sources: "Sources/**"
        ),
    ]
)
SWIFT

# -- Minimal source file
cat > "$FIXTURE_DIR/App/Sources/App.swift" <<'SWIFT'
import SwiftUI

@main
struct TestApp: App {
    var body: some Scene {
        WindowGroup { Text("test") }
    }
}
SWIFT

# -- StoreKit config
cat > "$FIXTURE_DIR/App/Config/Products.storekit" <<'JSON'
{
  "identifier" : "TEST",
  "nonRenewingSubscriptions" : [],
  "products" : [],
  "settings" : {},
  "subscriptionGroups" : [],
  "version" : { "major" : 2, "minor" : 0 }
}
JSON

# -- Generate
echo "==> Generating with: $TUIST_BIN"
(cd "$FIXTURE_DIR" && "$TUIST_BIN" generate --no-open)

# -- Verify
SCHEME_FILE="$FIXTURE_DIR/Workspace.xcworkspace/xcshareddata/xcschemes/Workspace-App.xcscheme"

if [ ! -f "$SCHEME_FILE" ]; then
    echo "FAIL: scheme file not found at $SCHEME_FILE"
    exit 1
fi

STOREKIT_ID=$(grep -A1 'StoreKitConfigurationFileReference' "$SCHEME_FILE" | grep 'identifier' | sed 's/.*identifier = "\(.*\)".*/\1/')

echo "==> StoreKit identifier in scheme: '$STOREKIT_ID'"

EXPECTED="App/Config/Products.storekit"

if [ "$STOREKIT_ID" = "$EXPECTED" ]; then
    echo "PASS: StoreKit path is correct ('$EXPECTED')"
    exit 0
else
    echo "FAIL: expected '$EXPECTED', got '$STOREKIT_ID'"
    if echo "$STOREKIT_ID" | grep -q '^\.\./'; then
        echo "  -> The path has a spurious '../' prefix (the known bug)"
    fi
    exit 1
fi
