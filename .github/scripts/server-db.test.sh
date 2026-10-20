#!/usr/bin/env bash
# Test database setup argument forwarding and migration failure guards.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../../server/mise/tasks/db" && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Exercise the real scripts without databases or a shared Mix VM.
cat > "$scratch/mix" <<'BASH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MIX_ARGUMENTS"
case "${MIGRATION_RESULT:-ok}" in
  missing) exit 0 ;;
  failure) exit 1 ;;
esac
printf 'Repo: Fixture.Repo\n  Status  Migration ID\n'
if [ "${MIGRATION_RESULT:-ok}" = pending ]; then
  printf '  down  20260101000000\n'
fi
BASH
chmod +x "$scratch/mix"
export PATH="$scratch:$PATH"
export MIX_ARGUMENTS="$scratch/arguments"

CI=1 bash "$SCRIPT_DIR/reset.sh" > "$scratch/output" 2>&1
if grep -q -- '--no-compile\|--no-deps-check' "$MIX_ARGUMENTS"; then
  echo 'Ordinary database setup must keep compilation and dependency checks.' >&2
  exit 1
fi
grep -q 'Ecto.Create.run' "$MIX_ARGUMENTS"
grep -q 'Ecto.Migrations.run' "$MIX_ARGUMENTS"

CI=1 bash "$SCRIPT_DIR/reset.sh" --no-compile --no-deps-check > "$scratch/output" 2>&1
grep -qx -- '--no-compile' "$MIX_ARGUMENTS"
grep -qx -- '--no-deps-check' "$MIX_ARGUMENTS"
if grep -qx -- '--create' "$MIX_ARGUMENTS"; then
  echo '--create must not be passed to mix run.' >&2
  exit 1
fi

for result in missing pending failure; do
  if CI=1 MIGRATION_RESULT="$result" bash "$SCRIPT_DIR/reset.sh" --no-compile --no-deps-check > "$scratch/output" 2>&1; then
    echo "Database setup incorrectly passed with migration result: $result" >&2
    exit 1
  fi
done

echo 'Database setup regression tests passed.'
