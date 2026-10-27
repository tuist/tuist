#!/usr/bin/env bash
set -euo pipefail

: "${TUIST_CLI_BINARY:?Set TUIST_CLI_BINARY to the freshly built tuist executable}"
FIXTURE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tuist-swift-cargo-cache.XXXXXX")
cleanup() {
    if [ "$?" = 0 ]; then rm -rf "$ROOT"; else printf 'Fixture retained at %s\n' "$ROOT" >&2; fi
}
trap cleanup EXIT
cp "$FIXTURE/Cargo.toml" "$FIXTURE/Cargo.lock" "$ROOT/"
cp -R "$FIXTURE/src" "$ROOT/src"
mkdir -p "$ROOT/cache"
cat > "$ROOT/wrapper" <<'WRAPPER'
#!/bin/sh
printf '%s\n' "$@" > "$TUIST_CARGO_SESSION/compiler-$$.args"
printf '%s\n' "CARGO_HOME=${CARGO_HOME-}" "CARGO_MANIFEST_DIR=${CARGO_MANIFEST_DIR-}" "OUT_DIR=${OUT_DIR-}" > "$TUIST_CARGO_SESSION/compiler-$$.context"
exec "$TUIST_CLI_BINARY" cargo __compiler "$@"
WRAPPER
chmod 700 "$ROOT/wrapper"
export RUSTC_WRAPPER="$ROOT/wrapper" CARGO_INCREMENTAL=0
export TUIST_CARGO_CACHE_DIR="$ROOT/cache"
export TUIST_CARGO_STARTED
TUIST_CARGO_STARTED=$(date +%s)
unset TUIST_CARGO_INNER_WRAPPER RUSTC_WORKSPACE_WRAPPER OUT_DIR || true

cd "$ROOT"
for scenario in cold warm corrupt; do
    export TUIST_CARGO_SESSION="$ROOT/$scenario-reports"
    mkdir -p "$TUIST_CARGO_SESSION"
    cargo build --locked --offline --target-dir "$ROOT/target"
    test "$("$ROOT/target/debug/tuist-cargo-cache-smoke")" = 42
    python3 - "$scenario" "$TUIST_CARGO_SESSION" <<'PY'
import json
from pathlib import Path
import sys
scenario, directory = sys.argv[1:]
reports = [json.loads(p.read_text()) for p in Path(directory).glob('cache-reports/*.json')]
hits = sum(r['hits'] for r in reports)
misses = sum(r['misses'] for r in reports)
assert (hits, misses) == ((1, 0) if scenario == 'warm' else (0, 1)), (scenario, hits, misses)
records = [json.loads(line) for p in Path(directory).glob('cache-details/*.ndjson') for line in p.read_text().splitlines()]
tasks = [r for r in records if r['record'] == 'task']
assert len(tasks) == 1 and tasks[0]['status'] == ('hit' if scenario == 'warm' else 'miss'), tasks
observations = [json.loads(p.read_text()) for p in Path(directory).glob('*.json')]
assert len(observations) == (1 if scenario == 'warm' else 2), (scenario, observations)
assert all(r['name'] != 'itoa' for r in observations) if scenario == 'warm' else any(r['name'] == 'itoa' for r in observations)
print(f'{scenario}: hits={hits}, misses={misses}, compiler executions={len(observations)}, executable output=42')
PY
    cargo clean --target-dir "$ROOT/target"
    if [ "$scenario" = warm ]; then
        python3 - "$ROOT/cache/blobs" <<'PY'
from pathlib import Path
import sys
blob = next(Path(sys.argv[1]).iterdir())
blob.write_bytes(b'corrupted fixture artifact')
PY
    fi
done
