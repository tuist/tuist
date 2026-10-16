#!/usr/bin/env bash
# Exercises a built production release against a private disposable PostgreSQL
# instance. Never reads a kubeconfig or connects to an existing database.
set -euo pipefail
atlas="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release="${1:-$atlas/_build/prod/rel/atlas}"
work="$(mktemp -d)"
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
  pg_ctl -D "$work/postgres" -m immediate -w stop >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
for tool in initdb pg_ctl psql createdb curl python3; do command -v "$tool" >/dev/null; done
test -x "$release/bin/atlas"
ports="$(python3 - <<'PY'
import socket
sockets = [socket.socket(), socket.socket()]
for s in sockets:
    s.bind(('127.0.0.1', 0))
print(*(s.getsockname()[1] for s in sockets))
PY
)"
read -r pg_port http_port <<< "$ports"
initdb -D "$work/postgres" --auth=trust > "$work/initdb.log"
pg_ctl -D "$work/postgres" -l "$work/postgres.log" -o "-p $pg_port -h 127.0.0.1 -k $work" -w start >/dev/null
createdb -h 127.0.0.1 -p "$pg_port" atlas_demo
psql -h 127.0.0.1 -p "$pg_port" -d atlas_demo -v ON_ERROR_STOP=1 > /dev/null <<'SQL'
CREATE ROLE atlas_demo_reader LOGIN;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE atlas_demo TO atlas_demo_reader;
GRANT USAGE ON SCHEMA public TO atlas_demo_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO atlas_demo_reader;
SQL
key="$(python3 -c 'import secrets,base64; print(base64.b64encode(secrets.token_bytes(32)).decode())')"
secret="$(python3 -c 'import secrets; print(secrets.token_hex(64))')"
common=(env -i "PATH=$PATH" "HOME=$HOME" 'ERL_FLAGS=+S 2:2' RELEASE_DISTRIBUTION=none ATLAS_DEMO_MODE=true CHROME_PATH= PHX_HOST=localhost
  "SECRET_KEY_BASE=$secret" "GUARDIAN_SECRET_KEY=$secret" "ENCRYPTION_KEY=$key" "PORT=$http_port")
owner_url="ecto://$(id -un)@127.0.0.1:$pg_port/atlas_demo"
reader_url="ecto://atlas_demo_reader@127.0.0.1:$pg_port/atlas_demo"
if "${common[@]}" "DATABASE_URL=${reader_url%/atlas_demo}/atlas" "$release/bin/atlas" eval ':ok' > "$work/production-database.log" 2>&1; then
  echo 'Demo release unexpectedly accepted a production database name' >&2
  exit 1
fi
grep -q 'dedicated DATABASE_URL' "$work/production-database.log"
if ! "${common[@]}" "DATABASE_URL=$owner_url" "$release/bin/atlas" eval 'Atlas.Release.migrate()' > "$work/migrate.log" 2>&1; then
  tail -100 "$work/migrate.log" >&2
  exit 1
fi
if "${common[@]}" "DATABASE_URL=$reader_url" "$release/bin/atlas" eval '{:ok, _} = Application.ensure_all_started(:atlas)' > "$work/empty-dataset.log" 2>&1; then
  echo 'Demo release unexpectedly accepted an unseeded database' >&2
  exit 1
fi
grep -q 'Seed the isolated Atlas demo database' "$work/empty-dataset.log"
if ! "${common[@]}" "DATABASE_URL=$owner_url" "$release/bin/atlas" eval 'Atlas.Release.seed_demo()' > "$work/seed.log" 2>&1; then
  tail -100 "$work/seed.log" >&2
  exit 1
fi
if "${common[@]}" "DATABASE_URL=$owner_url" "$release/bin/atlas" eval '{:ok, _} = Application.ensure_all_started(:atlas)' > "$work/owner.log" 2>&1; then
  echo 'Demo release unexpectedly accepted the owner credential' >&2
  exit 1
fi
grep -q 'SELECT-only role' "$work/owner.log"
psql -h 127.0.0.1 -p "$pg_port" -d atlas_demo -v ON_ERROR_STOP=1 -c 'GRANT UPDATE (name) ON users TO atlas_demo_reader' > /dev/null
if "${common[@]}" "DATABASE_URL=$reader_url" "$release/bin/atlas" eval '{:ok, _} = Application.ensure_all_started(:atlas)' > "$work/column-grant.log" 2>&1; then
  echo 'Demo release unexpectedly accepted a column-level write grant' >&2
  exit 1
fi
grep -q 'SELECT-only role' "$work/column-grant.log"
psql -h 127.0.0.1 -p "$pg_port" -d atlas_demo -v ON_ERROR_STOP=1 -c 'REVOKE UPDATE (name) ON users FROM atlas_demo_reader' > /dev/null
psql -h 127.0.0.1 -p "$pg_port" -d atlas_demo -v ON_ERROR_STOP=1 -c 'CREATE ROLE demo_write_role; GRANT UPDATE ON users TO demo_write_role; GRANT demo_write_role TO atlas_demo_reader' > /dev/null
if "${common[@]}" "DATABASE_URL=$reader_url" "$release/bin/atlas" eval '{:ok, _} = Application.ensure_all_started(:atlas)' > "$work/role-membership.log" 2>&1; then
  echo 'Demo release unexpectedly accepted inherited write privileges' >&2
  exit 1
fi
grep -q 'SELECT-only role' "$work/role-membership.log"
psql -h 127.0.0.1 -p "$pg_port" -d atlas_demo -v ON_ERROR_STOP=1 -c 'REVOKE demo_write_role FROM atlas_demo_reader' > /dev/null
psql -h 127.0.0.1 -p "$pg_port" -d atlas_demo -v ON_ERROR_STOP=1 -c "INSERT INTO users (id, email, inserted_at, updated_at) VALUES (gen_random_uuid(), 'non-demo@example.invalid', now(), now())" > /dev/null
if "${common[@]}" "DATABASE_URL=$reader_url" "$release/bin/atlas" eval '{:ok, _} = Application.ensure_all_started(:atlas)' > "$work/foreign-dataset.log" 2>&1; then
  echo 'Demo release unexpectedly served a non-demo user record' >&2
  exit 1
fi
grep -q 'non-demo records' "$work/foreign-dataset.log"
psql -h 127.0.0.1 -p "$pg_port" -d atlas_demo -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = 'non-demo@example.invalid'" > /dev/null
if "${common[@]}" "DATABASE_URL=$reader_url" STRIPE_API_KEY=forbidden "$release/bin/atlas" eval ':ok' > "$work/credential.log" 2>&1; then
  echo 'Demo release unexpectedly accepted Stripe credentials' >&2
  exit 1
fi
grep -q 'not permitted' "$work/credential.log"
"${common[@]}" "DATABASE_URL=$reader_url" PHX_SERVER=true "$release/bin/server" > "$work/server.log" 2>&1 &
server_pid=$!
ready=false
for _ in $(seq 1 150); do
  if curl -fsS "http://127.0.0.1:$http_port/ready" > /dev/null 2>&1; then ready=true; break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  sleep 0.2
done
if [[ "$ready" != true ]]; then tail -100 "$work/server.log" >&2; exit 1; fi
for path in / /demo; do
  status="$(curl -sS -o /dev/null -D "$work/entry.headers" -w '%{http_code}' -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$http_port$path")"
  test "$status" = 302
  grep -qi '^location: /commercial/sales/accounts' "$work/entry.headers"
done
for path in /commercial/sales/accounts /tasks /commercial/finance /commercial/finance/vendors /library/notes; do
  curl -fsS -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$http_port$path" > "$work/page.html"
  grep -q 'id="demo-badge"' "$work/page.html"
done
for path in /mcp /admin/users /auth/google /inference/v1/models; do
  status="$(curl -sS -o /dev/null -w '%{http_code}' -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$http_port$path")"
  test "$status" = 403
done
status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$http_port/api/slack/events")"
test "$status" = 403
printf '%s\n' 'Atlas demo release passed: migrations, seeds, reader boot, anonymous pages; rejected production database, empty/foreign data, owner/column/inherited write privileges, and integration credentials; denied APIs.'
