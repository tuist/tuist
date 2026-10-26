#!/usr/bin/env bash
# Test which pull request changes run the oldest supported ClickHouse shards.

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/server-clickhouse-floor.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

expect() {
  local expected="$1" description="$2" files="$3" actual
  printf '%s\n' "$files" > "$scratch/files.json"
  actual="$(bash "$SCRIPT" --files "$scratch/files.json" 2>/dev/null)"
  if [ "$actual" != "$expected" ]; then
    echo "Expected $expected for $description, got $actual." >&2
    exit 1
  fi
}

expect false "a docs-only change" '[{"filename": "server/README.md", "patch": "@@ -1 +1 @@\n-a\n+b"}]'
expect false "a LiveView change without queries" '[{"filename": "server/lib/tuist_web/live/runners_live.ex", "patch": "@@ -1 +1 @@\n-  <h1>Old</h1>\n+  <h1>New</h1>"}]'
expect false "a test-only change" '[{"filename": "server/test/tuist/runners_test.exs", "patch": "@@ -1 +1 @@\n+    assert ClickHouseRepo.all(query) == []"}]'
expect false "a removed query line" '[{"filename": "server/lib/tuist/runners.ex", "patch": "@@ -1,2 +1 @@\n-    |> ClickHouseRepo.all()\n context"}]'
expect false "an empty file list" '[]'

expect true "a ClickHouse migration" '[{"filename": "server/priv/ingest_repo/migrations/20261021000000_add_column.exs", "patch": "@@ -0,0 +1 @@\n+defmodule M do end"}]'
expect true "a renamed ClickHouse migration" '[{"filename": "server/priv/repo/migrations/x.exs", "previous_filename": "server/priv/ingest_repo/migrations/x.exs", "patch": ""}]'
expect true "the version module" '[{"filename": "server/lib/tuist/clickhouse_versions.ex", "patch": "@@ -1 +1 @@\n+  @oldest_tested_release \"25.8\""}]'
expect true "server configuration" '[{"filename": "server/config/runtime.exs", "patch": "@@ -1 +1 @@\n+config :tuist, :x, 1"}]'
expect true "a Mix lockfile change" '[{"filename": "server/mix.lock", "patch": "@@ -1 +1 @@\n+ \"ch\": {}"}]'
expect true "a mise lockfile change" '[{"filename": "mise.lock", "patch": "@@ -1 +1 @@\n+version = \"26.2\""}]'
expect true "the Server workflow" '[{"filename": ".github/workflows/server.yml", "patch": "@@ -1 +1 @@\n+  x: y"}]'
expect true "an added ClickHouseRepo call" '[{"filename": "server/lib/tuist/runners.ex", "patch": "@@ -1 +1,2 @@\n context\n+    |> ClickHouseRepo.all()"}]'
expect true "an added fragment" '[{"filename": "server/lib/tuist/builds/analytics.ex", "patch": "@@ -1 +1 @@\n+      select: fragment(\"quantileExact(0.5)(?)\", b.duration)"}]'
expect true "an added FINAL" '[{"filename": "server/lib/tuist/tests.ex", "patch": "@@ -1 +1 @@\n+    \"SELECT * FROM test_runs FINAL\""}]'
expect true "an added schema field type" '[{"filename": "server/lib/tuist/runners/job.ex", "patch": "@@ -1 +1 @@\n+    field :platform, Ch, type: \"LowCardinality(String)\""}]'
expect true "a source file without a patch" '[{"filename": "server/lib/tuist/huge.ex"}]'

if bash "$SCRIPT" push 2>/dev/null | grep -qx true; then :; else
  echo "Expected push events to run the floor shards." >&2
  exit 1
fi
if bash "$SCRIPT" merge_group 2>/dev/null | grep -qx true; then :; else
  echo "Expected merge queue events to run the floor shards." >&2
  exit 1
fi

# A failing GitHub API runs the shards rather than skipping them.
cat > "$scratch/gh" <<'BASH'
#!/usr/bin/env bash
exit 1
BASH
chmod +x "$scratch/gh"
if PATH="$scratch:$PATH" bash "$SCRIPT" pull_request tuist/tuist 1 2>/dev/null | grep -qx true; then :; else
  echo "Expected an unreadable pull request to run the floor shards." >&2
  exit 1
fi

# The label forces the shards on a pull request that would otherwise skip them.
cat > "$scratch/gh" <<'BASH'
#!/usr/bin/env bash
case "$2" in
  */labels) printf 'ci:clickhouse-floor\n' ;;
  *) printf '[[{"filename": "server/README.md", "patch": "+a"}]]\n' ;;
esac
BASH
if PATH="$scratch:$PATH" bash "$SCRIPT" pull_request tuist/tuist 1 2>/dev/null | grep -qx true; then :; else
  echo "Expected the ci:clickhouse-floor label to run the floor shards." >&2
  exit 1
fi

cat > "$scratch/gh" <<'BASH'
#!/usr/bin/env bash
case "$2" in
  */labels) printf 'documentation\n' ;;
  *) printf '[[{"filename": "server/README.md", "patch": "+a"}], [{"filename": "docs/x.md", "patch": "+b"}]]\n' ;;
esac
BASH
if PATH="$scratch:$PATH" bash "$SCRIPT" pull_request tuist/tuist 1 2>/dev/null | grep -qx false; then :; else
  echo "Expected an unlabelled docs-only pull request to skip the floor shards." >&2
  exit 1
fi

echo 'ClickHouse floor gate tests passed.'
