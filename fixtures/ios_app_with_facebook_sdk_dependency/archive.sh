#!/usr/bin/env bash

SCRIPT_DIR="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"

tuist generate --no-open --path $SCRIPT_DIR

for i in {1..10}; do
  echo "Running xcodebuild: iteration $i"
  xcodebuild -scheme "App" -workspace "${SCRIPT_DIR}/App.xcworkspace" \
             clean archive \
             CODE_SIGNING_ALLOWED=NO \
             CODE_SIGN_IDENTITY=""
done
