#!/bin/bash
# Install a set of Xcode versions from pre-staged .xips into
# /Applications/Xcode_<version>.app. Runs inside the Packer VM as
# part of the macos-xcode-image build.
#
# Each .xip is expected at:
#   /Users/admin/Downloads/xcode-xips/Xcode-<version>*.xip
# matching the filename xcodes' `download` command produces.
#
# xcodes installs each bundle to /Applications/Xcode-<version>.app
# (dash separator). We rename to underscore form to match
# GitHub-hosted's `/Applications/Xcode_<version>.app` layout, which
# is the path customer workflows expect when consulting
# `.xcode-version` files / `actions/setup-xcode`.
#
# This script does *not* run `xcode-select`, `xcodebuild -license
# accept`, `-runFirstLaunch`, or `-downloadAllPlatforms`. Those are
# done once at the end of the Packer build against the default
# Xcode (the first version passed) — those steps install
# system-wide content (simulator runtimes, dev tool licenses) that's
# shared across every co-installed Xcode.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: install-xcodes.sh VERSION..." >&2
  echo "  e.g. install-xcodes.sh 26.5.0 26.4.1 26.3 26.2.1 26.1 26.0.1" >&2
  exit 1
fi

source ~/.zprofile

if ! command -v xcodes >/dev/null 2>&1; then
  echo "xcodes not on PATH — Packer should have brew installed it before invoking" >&2
  exit 1
fi

XIPS_DIR="/Users/admin/Downloads/xcode-xips"

# Prime the sudo timestamp cache once. xcodes install needs sudo
# (--no-superuser exists but skips license-acceptance plumbing we
# need); priming up-front lets the per-version loop use bare sudo
# without re-prompting between iterations.
echo 'admin' | sudo -S -v

for v in "$@"; do
  echo "=== Installing Xcode $v ==="
  xip=$(ls "$XIPS_DIR"/Xcode-"$v"*.xip 2>/dev/null | head -n1 || true)
  if [ -z "$xip" ] || [ ! -f "$xip" ]; then
    echo "missing .xip for $v in $XIPS_DIR" >&2
    ls -la "$XIPS_DIR" >&2 || true
    exit 1
  fi
  echo "  source: $xip ($(du -h "$xip" | awk '{print $1}'))"

  # `--experimental-unxip` swaps the single-threaded xip extractor
  # for a parallel one — biggest single time saver in the loop.
  # `--empty-trash` reclaims the .xip from /Users/admin/.Trash
  # after install; without it, six installs would balloon
  # /Users/admin/.Trash past the disk budget.
  # No `--select` here: we let each install land without becoming
  # the active developer dir. Packer activates the default
  # (first argument) at the end of the build.
  sudo -n xcodes install "$v" --experimental-unxip --path "$xip" --empty-trash

  # xcodes installs to /Applications/Xcode-<version>.app (dash).
  # Glob covers any extra suffix xcodes might append in a future
  # release; head -n1 picks the deterministic one.
  installed=$(ls -d /Applications/Xcode-"$v"*.app 2>/dev/null | head -n1 || true)
  if [ -z "$installed" ] || [ ! -d "$installed" ]; then
    echo "could not locate installed Xcode bundle for $v" >&2
    ls -d /Applications/Xcode*.app 2>/dev/null >&2 || true
    exit 1
  fi

  target="/Applications/Xcode_$v.app"
  if [ "$installed" != "$target" ]; then
    sudo -n mv "$installed" "$target"
  fi
  echo "  installed: $target"
done

echo "=== All Xcode bundles installed ==="
ls -1d /Applications/Xcode_*.app
