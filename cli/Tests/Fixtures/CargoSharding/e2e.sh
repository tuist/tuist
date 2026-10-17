#!/usr/bin/env bash
set -euo pipefail

: "${TUIST_E2E_CLI:?Set TUIST_E2E_CLI to the built Tuist executable}"
: "${TUIST_PROJECT:?Set TUIST_PROJECT to an isolated Cargo project}"
: "${TUIST_URL:?Set TUIST_URL to the real server URL}"
: "${TUIST_TOKEN:?Provide a token authorized for the isolated project}"

fixture=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=${TUIST_CARGO_E2E_DIR:-$(mktemp -d /tmp/tuist-cargo-sharding-e2e.XXXXXX)}
mkdir -p "$work/planner"
printf 'Artifacts: %s\n' "$work"
python3 -c 'import time; print(time.time())' >"$work/started-at"
cp "$fixture/Cargo.toml" "$work/planner/"
cp -R "$fixture/src" "$fixture/tests" "$work/planner/"
TUIST_CARGO_EXECUTABLE=${TUIST_CARGO_EXECUTABLE:-$(rustup which cargo)}
TUIST_SHARD_REFERENCE="cargo-e2e-$(date +%s)-$$"
export TUIST_CARGO_EXECUTABLE TUIST_SHARD_REFERENCE
export TUIST_DEBUG=1
unset TUIST_SHARD_INDEX TUIST_SHARD_PLAN_ID TUIST_TEST_SHARD_ARCHIVE_PATH TUIST_CARGO_ACTIVE

(cd "$work/planner" && "$TUIST_E2E_CLI" cargo test-build --shard-total 2 >"$work/plan.json" 2>"$work/plan.log")
export TUIST_SHARD_PLAN_ID
TUIST_SHARD_PLAN_ID=$(
  python3 - "$work/plan.json" <<'PY'
import json,sys
plan=json.load(open(sys.argv[1]))
assert plan['shards']==[0,1], plan
print(plan['shard_plan_id'])
PY
)

cat >"$work/reject-compilation" <<'SH'
#!/bin/sh
for argument in "$@"; do
  case "$argument" in
    *.rs) echo "unexpected compilation: $*" >> "$TUIST_E2E_COMPILE_LOG"; exit 97 ;;
  esac
done
exec "$@"
SH
chmod +x "$work/reject-compilation"
export TUIST_E2E_COMPILE_LOG="$work/compilation.log"

for index in 0 1; do
  mkdir -p "$work/worker-$index"
  cp "$fixture/Cargo.toml" "$work/worker-$index/"
  cp -R "$fixture/src" "$fixture/tests" "$work/worker-$index/"
  (
    cd "$work/worker-$index"
    env TUIST_SHARD_INDEX=$index TUIST_E2E_EXECUTIONS="$work/executions-$index.txt" \
      RUSTC_WRAPPER="$work/reject-compilation" \
      "$TUIST_E2E_CLI" cargo nextest run -E 'all()' -E 'all()' >"$work/shard-$index.log" 2>&1
  )
done

python3 - "$work" <<'PY'
from pathlib import Path
from collections import Counter
import sys
root=Path(sys.argv[1])
a=root.joinpath('executions-0.txt').read_text().splitlines()
b=root.joinpath('executions-1.txt').read_text().splitlines()
expected={'unit_one','unit_two','api_one','api_two','storage_one','storage_two'}
assert not set(a)&set(b), (a,b)
assert Counter(a+b)==Counter(expected), (a,b)
assert not root.joinpath('compilation.log').exists(), 'Shard workers recompiled source'
assert 'failed to connect to jobserver' not in root.joinpath('plan.log').read_text(), 'Compiler observation lost Cargo jobserver descriptors'
print('PASS: six tests executed exactly once across two disjoint shards, with no worker compilation')
PY

python3 - "$work" <<'PY'
import os,json,sys,time,datetime,urllib.request
from pathlib import Path
root=Path(sys.argv[1])
started=float(root.joinpath('started-at').read_text())-2
url=os.environ['TUIST_URL'].rstrip('/')+'/api/projects/'+os.environ['TUIST_PROJECT']+'/tests'
request=urllib.request.Request(url, headers={'Authorization':'Bearer '+os.environ['TUIST_TOKEN']})
for attempt in range(20):
    try:
        with urllib.request.urlopen(request,timeout=30) as response:
            data=json.load(response)
    except (TimeoutError, urllib.error.URLError) as error:
        if attempt==19: raise
        time.sleep(2)
        continue
    runs=[r for r in data['test_runs'] if datetime.datetime.fromisoformat(r['ran_at'].replace('Z','+00:00')).timestamp()>=started]
    matches=[r for r in runs if r['total_test_count']==6 and r['status']=='success']
    if matches:
        root.joinpath('reported-run.json').write_text(json.dumps(matches[0],indent=2))
        print('PASS: the real server received all six tests in one successful merged run: '+matches[0]['id'])
        break
    time.sleep(2)
else:
    raise AssertionError(('The server did not receive a completed merged run', runs))
PY

expect_failure() {
  local label=$1
  shift
  if (cd "$work/worker-0" && "$@" >"$work/$label.log" 2>&1); then
    echo "FAIL: $label unexpectedly succeeded" >&2
    exit 1
  fi
}
export TUIST_E2E_EXECUTIONS="$work/unexpected-execution.txt"
expect_failure invalid-index env TUIST_SHARD_INDEX=99 "$TUIST_E2E_CLI" cargo nextest run
expect_failure missing-plan env TUIST_SHARD_INDEX=0 TUIST_SHARD_PLAN_ID=00000000-0000-4000-8000-000000000000 "$TUIST_E2E_CLI" cargo nextest run
python3 - "$work" <<'PY'
import json,os,sys,urllib.request
from pathlib import Path
root=Path(sys.argv[1])
url=os.environ['TUIST_URL'].rstrip('/')+'/api/projects/'+os.environ['TUIST_PROJECT']+'/tests/shards'
for name,granularity in [('missing-archive','module'),('incompatible-plan','suite')]:
    body={'reference':os.environ['TUIST_SHARD_REFERENCE']+'-'+name,'modules':['tuist-cargo-sharding-fixture'],'granularity':granularity,'shard_total':2}
    if granularity=='suite': body['test_suites']=['tuist-cargo-sharding-fixture/tests']
    request=urllib.request.Request(url,data=json.dumps(body).encode(),headers={'Authorization':'Bearer '+os.environ['TUIST_TOKEN'],'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=30) as response:
        plan=json.load(response)
    root.joinpath(name+'-id').write_text(plan['id'])
PY
missing_archive_id=$(<"$work/missing-archive-id")
incompatible_plan_id=$(<"$work/incompatible-plan-id")
expect_failure missing-archive env TUIST_SHARD_INDEX=0 TUIST_SHARD_PLAN_ID="$missing_archive_id" "$TUIST_E2E_CLI" cargo nextest run
expect_failure incompatible-plan env TUIST_SHARD_INDEX=0 TUIST_SHARD_PLAN_ID="$incompatible_plan_id" "$TUIST_E2E_CLI" cargo nextest run
grep -q 'Downloading the nextest shard archive failed' "$work/missing-archive.log"
grep -q 'module-granularity shard plan' "$work/incompatible-plan.log"
if test -s "$work/unexpected-execution.txt"; then
  echo 'FAIL: invalid shard configuration executed tests' >&2
  exit 1
fi
printf 'PASS: invalid index, missing plan, missing archive, and incompatible plan failed without executing tests\nPlan: %s\n' "$TUIST_SHARD_PLAN_ID"

mkdir -p "$work/worker-empty"
cp "$fixture/Cargo.toml" "$work/worker-empty/"
cp -R "$fixture/src" "$fixture/tests" "$work/worker-empty/"
(cd "$work/worker-empty" && env TUIST_SHARD_INDEX=0 TUIST_E2E_EXECUTIONS="$work/empty-execution.txt" RUSTC_WRAPPER="$work/reject-compilation" "$TUIST_E2E_CLI" cargo nextest run -E 'none()' >"$work/empty-shard.log" 2>&1)
if test -s "$work/empty-execution.txt" || test -e "$work/compilation.log"; then
  echo 'FAIL: empty selection ran tests or compiled source' >&2
  exit 1
fi
printf 'PASS: empty filter intersection succeeded without tests or compilation\nArtifacts: %s\n' "$work"
