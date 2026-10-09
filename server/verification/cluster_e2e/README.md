# Complete two-server verification

This standalone harness boots two complete server processes and sends requests
through a round-robin proxy. It uses the real router, authentication, tool
handlers, database, image renderer, object storage, and shared rate limiter.
It is deliberately outside automatic ExUnit discovery because it requires
dedicated services and terminates/restarts server processes.

The assertions include 400 concurrent real `/api/cache/access` requests using both project and account tokens at bcrypt cost 12, verifying exactly one bcrypt call per credential per replica and immediate revocation afterward. This catches the traffic class missed by the original JWT/user-token-only verification.

The assertions also cover stateless Model Context Protocol calls, credential and
permission revocation, cache and feature-flag invalidation, discovery after a
distribution disconnect, concurrent image generation, marketing-owner takeover,
supervised-task draining, rolling restart, a shared admission budget, and
shared-store timeout/recovery. Three headless Chrome screenshots capture the
public discovery card before departure, during single-server operation, and
after rejoin. Do not treat results from the original, reverted rollout as validation of this restoration. Screenshots stay outside the branch and belong in pull request attachments.

## Dedicated local services

Use disposable test data only. The harness inserts users, organizations,
projects, and feature flags. It writes objects and temporarily pauses its Redis
instance. Do not point it at production or a shared Redis instance.

Prepare these services before running, keeping their launch processes alive:

| Service | Configuration |
| --- | --- |
| PostgreSQL | `127.0.0.1:14106`, user `scale_e2e`, local trust authentication, migrated database `tuist_test_scale_out` |
| ClickHouse | `127.0.0.1:8123`, migrated isolated database `tuist_test_scale_out` |
| MinIO | `127.0.0.1:14103`, console `14104`, user `test`, password `testpassword`, dedicated object directory |
| Redis | `127.0.0.1:14105`, persistence disabled, dedicated process |

The recorded run initialized a private PostgreSQL data directory with `initdb`,
started it with `pg_ctl`, created the database with `createdb`, and loaded a
`pg_dump --no-owner --no-acl` export of the locally migrated synthetic test
database using `psql`. The ClickHouse database was created and migrated with
the server's normal repository tasks. No production database was copied.

For example, start the object store and limiter in separate terminals:

```sh
mkdir -p /tmp/tuist-scale-e2e/objects
MINIO_ROOT_USER=test MINIO_ROOT_PASSWORD=testpassword minio server \
  /tmp/tuist-scale-e2e/objects --address 127.0.0.1:14103 \
  --console-address 127.0.0.1:14104
redis-server --bind 127.0.0.1 --port 14105 --save '' --appendonly no
```

Compile the server in the test environment first using `MIX_ENV=test mix compile`.
The server's compiled test fixtures and a working local Chrome installation are
required. The default browser path is the macOS Chrome application.

## Run

Choose a second existing local IPv4 address distinct from `127.0.0.1`; the
recorded run used the machine's private network address. Both Erlang listeners
bind their own address, while both web listeners bind separate loopback ports.
Ensure ports `14100`, `14101`, `14102`, `15353`, and `19110` are available.

From `server/`, start discovery and the proxy in a separate terminal:

```sh
export TUIST_E2E_SECOND_ADDRESS=192.168.1.116 # Replace with your local address.
python3 verification/cluster_e2e/services.py
```

Then run the controller, using the same second address:

```sh
export TUIST_E2E_SECOND_ADDRESS=192.168.1.116 # Replace with your local address.
export TUIST_E2E_REDIS_CLI="$(command -v redis-cli)"
export MIX_ENV=test
export TUIST_SERVER_TEST_POSTGRES_DB=tuist_test_scale_out
export TUIST_SERVER_TEST_CLICKHOUSE_DB=tuist_test_scale_out
export TUIST_S3_BUCKET_NAME=scale-e2e
export TUIST_REDIS_URL=redis://127.0.0.1:14105
export ERL_FLAGS='+S 2:2'
mkdir -p /tmp/tuist-scale-e2e
elixir --hidden --name e2e_control@127.0.0.1 --cookie scale_e2e_verification \
  -S mix run --no-compile --no-start verification/cluster_e2e/run.exs
```

Success ends with `All full-server end-to-end checks passed` and exit status
zero. The controller terminates the two server processes after assertions.
The service terminals and private databases are owned by the person running
the harness and must be stopped afterward. Logs, process identifiers,
task markers, and screenshots are written under `/tmp/tuist-scale-e2e`.
If startup fails before the assertion cleanup is installed, use the recorded
`server-14101.pid` and `server-14102.pid` to identify and stop only those owned
processes. Server diagnostic logs can contain synthetic credentials; retain
only the `PASS:` assertion lines when sharing results.

## Authentication-only load run

Set `TUIST_E2E_TOKEN_LOAD_ONLY=1` to run the two-server discovery and project/account-token HTTP load/revocation checks, then stop both owned server processes. This mode needs only the disposable PostgreSQL and ClickHouse databases plus the discovery/proxy process; it does not need Redis, MinIO or Chrome. Leave `TUIST_REDIS_URL` unset. The complete run above remains the gate for images, shared admission and shutdown/failover behavior.

For a dedicated database on an existing local PostgreSQL service, override `TUIST_E2E_POSTGRES_PORT`, `TUIST_E2E_POSTGRES_USER` and `TUIST_E2E_POSTGRES_PASSWORD`. The default remains port 14106 with user `scale_e2e` and no password. `TUIST_E2E_OUTPUT_DIR` selects a separate directory for server logs and PID files; defaults to `/tmp/tuist-scale-e2e`.

### Diverse-token cache lifecycle run

Also set `TUIST_E2E_TOKEN_CACHE_STRESS=1` to exercise 128 distinct credentials (64 project tokens and 64 account tokens), at production bcrypt cost, against both real server processes. Use it with `TUIST_E2E_TOKEN_LOAD_ONLY=1` and the same controller command above.

The additional run sends 7,680 authenticated HTTP requests at concurrency 32. It asserts exact bcrypt counts for cold and warm traffic, waits for the actual one-minute proof TTL, restarts one replica and verifies that the surviving replica keeps its proofs, then forces LRW pruning on one replica and verifies that only evicted proofs are recomputed. Repeated warm phases must perform zero bcrypt calls. Each phase also samples `/ready` and reports request/readiness latency.

These phases address each backend directly on its loopback HTTP port so every credential is exercised on both replicas. The initial 400-request/revocation check still uses the round-robin proxy. Restart traffic is measured after membership has recovered, not continuously during the restart; this does not replace the complete rolling-restart, image and shared-limiter checks. Expect several minutes of runtime because credential creation and cache misses use rounds 12 and expiry uses the real production TTL.

## Verification boundaries

Each server uses the complete application under the test build, replacing
database sandbox pools with ordinary connection pools and enabling asynchronous
supervised tasks. Scheduled jobs remain disabled. Unlike normal ExUnit, bcrypt uses 12 rounds; both project and account tokens exercise the real authentication plug. The normal marketing process,
normally excluded from test startup, is explicitly started. Test-profile
ingestion remains synchronous; this run does not validate production buffer
durability after a hard kill.

The default Kubernetes address-discovery strategy queries a real local
[Domain Name System](https://www.rfc-editor.org/rfc/rfc1035) responder. Its
configuration applies only inside these Erlang processes and does not change
the machine's resolver. The observer is hidden from normal cluster membership.
Both servers use long names with the same prefix and distinct host addresses.
Fixed-port lookup (`-erl_epmd_port 19110`) handles the single machine's shared
[Erlang port mapper](https://www.erlang.org/doc/apps/erts/epmd_cmd.html); it
does not exercise separate Kubernetes pod port mappers or network policies.
The distribution partition is simulated by changing the peer cookie and
disconnecting the nodes. Healing restores that cookie and relies on ordinary
discovery. No packet-drop fault or live deployment is involved.
