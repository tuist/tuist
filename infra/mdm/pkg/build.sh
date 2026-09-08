#!/bin/sh
# Builds the signed bootstrap package the MDM pushes at enrollment via
# InstallEnterpriseApplication. Run on a Mac with the Developer ID
# Installer identity in the login keychain.
#
# Usage:
#   ./build.sh <fleet-ssh-public-key-file> "Developer ID Installer: ..." [service-account]
#
# Output: tuist-runner-bootstrap.pkg (signed product archive) in the
# working directory, plus its base64 form for the 1Password field.
set -eu

KEY_FILE=${1:?fleet SSH public key file}
SIGN_IDENTITY=${2:?Developer ID Installer signing identity}
SVC_ACCOUNT=${3:-tuist}
VERSION=${VERSION:-1.0.0}
IDENTIFIER=dev.tuist.runner-bootstrap

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/scripts"
# Substituted with python rather than sed: a real authorized_keys file
# holds several keys, and sed treats the embedded newline as the end of
# the substitution and dies with "unterminated `s' command". Key comments
# containing the delimiter would break it too.
SVC_ACCOUNT="$SVC_ACCOUNT" KEY_FILE="$KEY_FILE" python3 - \
    "$SRC_DIR/postinstall.tmpl" "$WORK_DIR/scripts/postinstall" <<'PYEOF'
import os, sys

template, out = sys.argv[1], sys.argv[2]
keys = open(os.environ["KEY_FILE"]).read().strip()
body = open(template).read()
body = body.replace("@SVC_ACCOUNT@", os.environ["SVC_ACCOUNT"])
body = body.replace("@AUTHORIZED_KEYS@", keys)
open(out, "w").write(body)
PYEOF
chmod 755 "$WORK_DIR/scripts/postinstall"

pkgbuild --nopayload \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --scripts "$WORK_DIR/scripts" \
  "$WORK_DIR/component.pkg"

productbuild --package "$WORK_DIR/component.pkg" "$WORK_DIR/unsigned.pkg"

productsign --sign "$SIGN_IDENTITY" "$WORK_DIR/unsigned.pkg" tuist-runner-bootstrap.pkg

pkgutil --check-signature tuist-runner-bootstrap.pkg

base64 -i tuist-runner-bootstrap.pkg -o tuist-runner-bootstrap.pkg.b64
echo "Wrote tuist-runner-bootstrap.pkg and .b64 (for the 1Password bootstrap-pkg-b64 field)."
