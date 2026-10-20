#!/usr/bin/env bash
#
# Names in the macOS image chain, as `key=value` lines for $GITHUB_OUTPUT or
# `eval`.
#
#   macos-image-names.sh major <macOS major>     e.g. 26, 27
#   macos-image-names.sh profile <profile>       e.g. 27.1, golden-gate-27.1
#
# Each macOS major has its own chain, named after its codename: the vendor
# base `ghcr.io/cirruslabs/macos-<codename>-base`, the Xcode layer
# `ghcr.io/tuist/macos-<codename>-xcode:<xcode-dashes>` and runner images
# `ghcr.io/tuist/tuist-runner:macos-<profile-dashes>`. A runner image profile
# (an entry in infra/runner-image/profiles.json) is the Xcode version for a
# macOS 26 guest, which keeps every name that predates the other majors, and
# `<codename>-<xcode>` for any other.
#
# A guest can only be built and booted on a host running the same macOS major
# or newer, so a major past 26 also names the extra builder label
# (`macos-<major>`) its builds need. Kept in step with the chart's
# `tuist.macosCodename`.
set -euo pipefail

codename_for() {
  case "$1" in
    26) echo tahoe ;;
    27) echo golden-gate ;;
    *)
      echo "macOS $1 has no image chain; add its codename to $0 and tuist.macosCodename" >&2
      return 1
      ;;
  esac
}

major_for() {
  case "$1" in
    tahoe) echo 26 ;;
    golden-gate) echo 27 ;;
    *)
      echo "no macOS major has the codename $1" >&2
      return 1
      ;;
  esac
}

emit() {
  local major="$1" codename runs_on
  codename="$(codename_for "$major")"
  runs_on='["self-hosted","macos","bare-metal","vm-image-builder"]'
  if [ "$major" != 26 ]; then
    runs_on="${runs_on%]},\"macos-${major}\"]"
  fi
  echo "major=${major}"
  echo "codename=${codename}"
  echo "vendor_base=ghcr.io/cirruslabs/macos-${codename}-base:latest"
  echo "xcode_image=macos-${codename}-xcode"
  echo "xcode_repository=ghcr.io/tuist/macos-${codename}-xcode"
  echo "runs_on=${runs_on}"
}

case "${1:-}" in
  major)
    emit "${2:?macOS major required}"
    ;;
  profile)
    profile="${2:?runner image profile required}"
    if [[ "$profile" =~ ^([a-z]+(-[a-z]+)*)-([0-9].*)$ ]]; then
      major="$(major_for "${BASH_REMATCH[1]}")"
      xcode="${BASH_REMATCH[3]}"
    else
      major=26
      xcode="$profile"
    fi
    emit "$major"
    echo "xcode_version=${xcode}"
    echo "xcode_tag=${xcode//./-}"
    echo "runner_tag=macos-${profile//./-}"
    ;;
  *)
    echo "usage: $0 major <macOS major> | profile <runner image profile>" >&2
    exit 64
    ;;
esac
