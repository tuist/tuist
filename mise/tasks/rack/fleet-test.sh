#!/usr/bin/env bash
#MISE description="Run the rack switch fleet tests (bats)"
#
# Everything here runs against a committed transcript taken off a live switch
# and against a fake switch on PATH, so the suite needs no hardware.
#
# Each file under infra/rack-switch-fleet/tests runs as its own bats process,
# all of them side by side: each file works on its own copy of the fleet (see
# tests/helpers.bash), and most of the suite's time is fake switches waiting
# out the session driver's quiet window rather than work. A file's output is
# printed whole once it finishes, in the order the files are named, with
# what a failing test printed.
#
#   mise run rack:fleet-test               # every file
#   mise run rack:fleet-test render edge   # what a change to the site definition touches

set -euo pipefail

root="$(git rev-parse --show-toplevel)"
tests="$root/infra/rack-switch-fleet/tests"

files=()
if (( $# )); then
  for name in "$@"; do
    if [ ! -f "$tests/$name.bats" ]; then
      known=""
      for file in "$tests"/*.bats; do known+=" $(basename "$file" .bats)"; done
      echo "error: no test file $name.bats; known:$known" >&2
      exit 2
    fi
    files+=("$tests/$name.bats")
  done
else
  for file in "$tests"/*.bats; do files+=("$file"); done
fi

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

pids=()
for i in "${!files[@]}"; do
  (
    start=$SECONDS
    status=0
    bats --print-output-on-failure "${files[$i]}" > "$out/$i" 2>&1 || status=$?
    echo $(( SECONDS - start )) > "$out/$i.seconds"
    exit "$status"
  ) &
  pids+=("$!")
done

failed=()
for i in "${!files[@]}"; do
  status=0
  wait "${pids[$i]}" || status=$?
  name="$(basename "${files[$i]}" .bats)"
  echo "=== $name ($(cat "$out/$i.seconds")s)"
  cat "$out/$i"
  (( status == 0 )) || failed+=("$name")
done

if (( ${#failed[@]} )); then
  echo "failed: ${failed[*]}" >&2
  exit 1
fi
echo "all ${#files[@]} test files passed"
