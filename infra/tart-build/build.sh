#!/usr/bin/env bash
# Builds upstream Tart <version> with the patches beside this script into the
# tart.tar.gz layout the CAPI provider image ships (see TART_RELEASES in
# infra/cluster-api-provider-tuist/Dockerfile), versioned <version>-tuist.<n>.
#
# The patches add `tart run --usb-disk-requests`, which hot-plugs DiskImageKit
# stacks into a running VM as USB disks: the block-device cache volumes in
# infra/tart-kubelet/AGENTS.md. The build is signed ad hoc with only the
# virtualization entitlement: fleet hosts run VMs on NAT networking, which needs
# no provisioning profile.
#
# Usage, on a Mac with Xcode 27 or newer: build.sh 2.41.1 1 out/tart.tar.gz
set -euo pipefail

upstream="${1:?upstream Tart version, such as 2.41.1}"
revision="${2:?Tuist build revision, such as 1}"
output="${3:?output tar.gz path}"
version="${upstream}-tuist.${revision}"
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone -q --depth 1 --branch "$upstream" https://github.com/openai/tart "$work/src"
for patch in "$here"/patches/*.patch; do
  git -C "$work/src" apply "$patch"
done
perl -pi -e "s/\\\$\\{VERSION\\}/${version}/g" "$work/src/Sources/tart/CI/CI.swift"
(cd "$work/src" && swift build --configuration release --product tart)

app="$work/out/tart.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(cd "$work/src" && swift build --configuration release --show-bin-path)/tart" "$app/Contents/MacOS/tart"
cp "$work/src/Resources/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${version}" "$app/Contents/Info.plist"
cp "$work/src/Resources/actool/UPW Tart.icns" "$work/src/Resources/actool/Assets.car" "$app/Contents/Resources/"
cp "$work/src/LICENSE" "$work/out/LICENSE"
cat >"$work/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.virtualization</key>
	<true/>
</dict>
</plist>
PLIST
codesign --force --sign - --entitlements "$work/entitlements.plist" "$app"
codesign --verify --strict "$app"
"$app/Contents/MacOS/tart" --version

mkdir -p "$(dirname "$output")"
tar -C "$work/out" -czf "$output" tart.app LICENSE
shasum -a 256 "$output"
