#!/usr/bin/env bash

tuist generate --no-open
xcodebuild archive -workspace App.xcworkspace -scheme App -config Release  -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
