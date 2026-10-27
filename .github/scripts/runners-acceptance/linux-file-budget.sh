#!/usr/bin/env bash
# RLIMIT_NOFILE alone misses virtiofsd's separate per-inode descriptor budget.
# Keep more files than Kata's default permits, using only a disposable job path.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
work="$(mktemp -d "$HOME/runner-file-budget.XXXXXX")"
trap 'rm -rf "$work"' EXIT
for directory in $(seq 1 120); do
  mkdir "$work/$directory"
  if ! (cd "$work/$directory" && seq 1 10000 | xargs touch); then
    fail 'Linux rootfs file budget' "could not create 1.2 million files; failed after $(((directory - 1) * 10000)) files"
  fi
done
pass 'Linux rootfs file budget: kept 1.2 million files without exhausting virtiofsd descriptors'
