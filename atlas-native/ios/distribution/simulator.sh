#!/usr/bin/env bash
set -euo pipefail

app="${1:?Pass the delivery simulator app bundle}"
bash "$(dirname "$0")/version.sh" "$app"
# Updating Info.plist invalidates the bundle signature, including its Keychain entitlement.
codesign --force --sign - --timestamp=none --preserve-metadata=entitlements "$app"
codesign --verify --deep --strict "$app"
