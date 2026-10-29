#!/bin/sh
set -eu
xcodebuild -project /tmp/tuist-resume-fixture/Frameworks/Frameworks.xcodeproj \
  -scheme iOS -sdk iphonesimulator \
  -derivedDataPath /tmp/tuist-resume-fixture/DerivedData \
  CODE_SIGNING_ALLOWED=NO build -quiet
# Verify that the same simulator remains booted after the VM is restored.
# Explicitly select the native slice of the host's universal executable.
# An implicit x86_64 selection cannot load this ARM simulator's dyld cache.
xcrun simctl spawn --arch=arm64 "$(cat /tmp/tuist-resume-fixture/simulator)" /usr/bin/true
