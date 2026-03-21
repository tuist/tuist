#!/bin/bash

valid_team="U6LC622NKF"
for path in "$(which tuist)" "$(dirname "$(which tuist)")/ProjectDescription.framework"; do
  if ! codesign -d --verbose=4 "$path" 2>&1 | grep -q "TeamIdentifier=*$valid_team"; then
    echo "The binary at $path is not signed by the Tuist team."
    return 1
  fi
done
echo "The Tuist binaries are valid."
