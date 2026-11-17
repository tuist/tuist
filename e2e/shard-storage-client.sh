#!/usr/bin/env bash
# Real CLI workflows; unlike the byte probe these execute compiled test products.
set -euo pipefail
umask 077
: "${TUIST_URL:?}"
: "${TUIST_PROJECT:?}"
: "${TUIST_TOKEN:?}"
: "${TUIST_E2E_CLI:?Absolute path to the CLI under test}"
: "${SHARD_STORAGE_HOST:?Expected RustFS or baseline Tigris hostname}"
[[ "$TUIST_URL" == https://staging.tuist.dev ]] || { echo 'Staging only' >&2; exit 1; }
[[ "$TUIST_PROJECT" =~ ^[a-zA-Z0-9_-]+/rustfs-e2e-[a-zA-Z0-9_-]+$ ]] || { echo 'Dedicated rustfs-e2e-* project required' >&2; exit 1; }
[[ "$TUIST_E2E_CLI" == /* && -x "$TUIST_E2E_CLI" ]] || exit 1
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/rustfs-client.XXXXXX")
# Existing Cargo debug logs can contain signed URLs. Never publish them.
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$work"; else echo "Private diagnostics retained at $work; do not publish raw logs." >&2; fi' EXIT
unset TUIST_DEBUG TUIST_SHARD_INDEX TUIST_SHARD_PLAN_ID
case "${1:-}" in
  cargo)
    export TUIST_CARGO_E2E_DIR="$work/cargo"
    if ! bash "$repo/cli/Tests/Fixtures/CargoSharding/e2e.sh" >"$work/client.log" 2>&1; then
      echo 'FAIL: Cargo CLI workflow' >&2
      exit 1
    fi
    plan_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["shard_plan_id"])' "$work/cargo/plan.json")
    python3 "$repo/e2e/shard-storage.py" --storage-host "$SHARD_STORAGE_HOST" --check-plan "$plan_id"
    echo 'PASS: real Cargo workflow; six tests exactly once, no worker compilation'
    ;;
  xcode)
    [[ $(uname -s) == Darwin ]] || { echo 'Xcode workflow requires macOS' >&2; exit 1; }
    cp -R "$repo/examples/xcode/generated_ios_app_with_tests" "$work/planner"
    cat >"$work/planner/Tuist.swift" <<EOF
import ProjectDescription
let tuist = Tuist(fullHandle: "$TUIST_PROJECT", url: "$TUIST_URL", project: .tuist())
EOF
    # A source-only worker cannot accidentally reuse the planner's products.
    cp -R "$work/planner" "$work/worker"
    export TUIST_SHARD_REFERENCE="rustfs-e2e-$(date +%s)-$$"
    if ! "$TUIST_E2E_CLI" test MacFrameworkTests --build-only --shard-total 1 \
        --path "$work/planner" -- -testProductsPath "$work/products.xctestproducts" \
        -destination platform=macOS >"$work/build.log" 2>&1; then
      echo 'FAIL: Xcode build/upload' >&2
      exit 1
    fi
    # Resolve by reference to learn the ID without parsing potentially sensitive logs.
    plan_id=$(python3 - "$repo/e2e/shard-storage.py" <<'PY'
import importlib.util, os, sys, urllib.parse
spec=importlib.util.spec_from_file_location("probe", sys.argv[1])
probe=importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
base=os.environ["TUIST_URL"]+"/api/projects/"+os.environ["TUIST_PROJECT"]+"/tests/shards"
print(probe.api(base, "/"+urllib.parse.quote(os.environ["TUIST_SHARD_REFERENCE"], safe="")+"/0")["shard_plan_id"])
PY
    )
    python3 "$repo/e2e/shard-storage.py" --storage-host "$SHARD_STORAGE_HOST" --check-plan "$plan_id"
    rm -rf "$work/planner" "$work/products.xctestproducts"
    if ! "$TUIST_E2E_CLI" test MacFrameworkTests --without-building --shard-index 0 \
        --path "$work/worker" -- -destination platform=macOS >"$work/test.log" 2>&1; then
      echo 'FAIL: Xcode fresh-worker test' >&2
      exit 1
    fi
    echo 'PASS: real Xcode shard execution from remote products in a fresh source checkout'
    ;;
  *) echo 'Usage: bash e2e/shard-storage-client.sh cargo|xcode' >&2; exit 1 ;;
esac
