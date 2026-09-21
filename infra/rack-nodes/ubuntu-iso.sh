#!/usr/bin/env bash
# Fetch and verify the Ubuntu Server ISO for a release, cached between runs.
# Sourced by the rack:* tasks; prints the path to the verified image.

ensure_ubuntu_iso() {
  local release="$1"
  local cache="${XDG_CACHE_HOME:-$HOME/Library/Caches}/tuist-rack"
  local base="https://releases.ubuntu.com/$release"

  mkdir -p "$cache"
  local sums="$cache/SHA256SUMS-$release"
  curl -fsSL "$base/SHA256SUMS" -o "$sums"

  local name
  name="$(awk '/live-server-amd64\.iso$/{print $2}' "$sums" | tr -d '*' | head -1)"
  if [ -z "$name" ]; then
    echo "error: no live-server-amd64 ISO listed for Ubuntu $release" >&2
    return 1
  fi

  local iso="$cache/$name"
  if [ ! -f "$iso" ]; then
    echo "downloading $name" >&2
    curl -fL --progress-bar "$base/$name" -o "$iso.partial"
    mv "$iso.partial" "$iso"
  fi

  local expected actual
  expected="$(awk -v n="$name" '$2 == "*"n || $2 == n {print $1}' "$sums" | head -1)"
  actual="$(shasum -a 256 "$iso" | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    echo "error: checksum mismatch for $name" >&2
    echo "  expected $expected" >&2
    echo "  actual   $actual" >&2
    echo "  delete $iso and retry" >&2
    return 1
  fi

  echo "$iso"
}
