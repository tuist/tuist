#!/usr/bin/env bash
set -euo pipefail

source_dir="${KEEPER_SOURCE_DIR:-/legacy}"
target_dir="${KEEPER_TARGET_DIR:-/local}"
member_id="${HOSTNAME##*-}"
marker="$target_dir/.tuist-keeper-member"

if [[ -f "$marker" ]]; then
  [[ "$(cat "$marker")" == "$member_id" ]] || { echo 'Keeper member identity mismatch' >&2; exit 1; }
  exit 0
fi

# A retry must never overlay a partial copy or overwrite newer Raft state.
[[ -z "$(find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
  echo 'Destination is not empty and has no completed migration marker; inspect it while this member is stopped' >&2
  exit 1
}
[[ -d "$source_dir/log" && -d "$source_dir/snapshots" ]] || {
  echo 'Source does not contain the complete Keeper coordination directory' >&2
  exit 1
}
[[ -n "$(find "$source_dir/log" -type f -print -quit)" ]] || {
  echo 'Refusing to migrate an empty Keeper log' >&2
  exit 1
}

# The old process must have stopped cleanly before this init container runs.
# Include snapshots, logs, Raft state and any version-specific metadata.
cp -a "$source_dir/." "$target_dir/"
sync
printf '%s\n' "$member_id" > "$marker"
sync
