# Public read-only Atlas demo

The demo uses the normal Atlas image in a separate `atlas-demo` namespace, with
its own PostgreSQL database named `atlas_demo` and independent application keys.
It must never use a production database, Secret, restored production dataset,
object-storage bucket, or connector identity. Do not layer demo values over
`values-managed-production.yaml`.

## Provisioning

1. Provision PostgreSQL in `atlas-demo`, labeling its pods
   `app.kubernetes.io/name: atlas-demo-postgres`. The demo chart's egress policy
   permits only those pods on port 5432 and cluster DNS. Adjust both selectors
   in `demo` values if the PostgreSQL operator uses different labels. A CNI that
   enforces NetworkPolicy is required.
2. Create the `atlas_demo` database with a migration owner and a separate login
   with no role memberships and SELECT-only access. The public server must not
   connect as the owner or a superuser. For example, run the following as the
   migration owner inside this database (provision passwords separately):

   ```sql
   REVOKE CREATE ON SCHEMA public FROM PUBLIC;
   GRANT CONNECT ON DATABASE atlas_demo TO atlas_demo_reader;
   GRANT USAGE ON SCHEMA public TO atlas_demo_reader;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO atlas_demo_reader;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public
     GRANT SELECT ON TABLES TO atlas_demo_reader;
   ```

3. Provision `atlas-demo-app` and `atlas-demo-migrator` Secrets. Each contains
   `DATABASE_URL`, `SECRET_KEY_BASE`, `GUARDIAN_SECRET_KEY`, and `ENCRYPTION_KEY`.
   Both URLs end in `/atlas_demo`; the application uses the reader and migrations
   use the owner. Use fresh keys, not production keys. Do not include integration
   credentials. Runtime validation allowlists Atlas settings and rejects provider
   configuration; even a newly introduced `ATLAS_*` integration is denied by default.
4. Render and review the standalone chart with `values-demo.yaml`, pinning the
   same published chart/image version as Atlas production. The init container
   runs migrations and `Atlas.Release.seed_demo()` without starting the web app
   or workers. It inserts only deterministic fictional records, using schema
   writes rather than domain operations that enqueue jobs.
5. Deploy into `atlas-demo` only after reviewing the rendered Secrets references,
   egress policy, host, and database credentials. Point `demo.atlas.tuist.dev` at
   this deployment and apply the normal public-site edge rate limits, including
   limits on LiveView connections. No live provisioning or deployment is implied
   by adding the configuration to the repository.

## Safety and maintenance

- Serving connections set `default_transaction_read_only=on` in addition to the
  SELECT-only role. Database permissions are the durable barrier, not the session
  setting alone. Startup verifies the database name, session setting, role flags,
  lack of role memberships and ownership, and lack of write privileges on every
  public table. Owner credentials fail before the endpoint starts.
  Migrations/seeding use a separate credential and do not start `Atlas.Application`.
- Demo startup checks that every record in the exposed tables has the dedicated
  deterministic demo ID prefix, and refuses an empty/unseeded dataset. Seeding
  refuses non-demo rows too. This catches accidentally restored databases; it
  does not make importing production data safe.
- The serving supervisor omits Oban, GitHub bootstrap, self-monitoring, Guardian
  sweeps, ClickHouse, and browser pools. HTTP has a page allowlist; LiveView has
  per-view event and path allowlists. Unknown actions fail closed. Uploads are not
  registered on demo account pages. API, MCP, inference, auth, public verification,
  downloads, and administrator routes are unavailable.
- Keep pages curated. Before adding a page, review its mount, handle_params,
  handle_info, async tasks, nested components, and read-query dependencies for
  writes and upstream calls, then add positive and negative integration tests.
- Fictional dates are relative to the last seed run. Upgrading/restarting seeds
  idempotently, serialized by a transaction-scoped advisory lock. The dataset
  includes eighteen months of fictional cash flows and available cash for useful
  runway charts. Refresh with a weekly rollout so tasks and renewals stay current.
  Do not reuse the large development seed script.
- No paid inference or writable visitor sandbox is included. Disabled actions
  receive a read-only explanation, not a pretend success. Visitors land directly
  on Accounts; the navbar links to the documentation and self-hosting guide.

## Validation

Run from `atlas/` after fetching dependencies:

```sh
mix assets.build
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite
bash deploy/test-demo-release.sh
bash ../infra/helm/atlas/test-demo-boundary.sh
mix precommit test/atlas/demo/config_test.exs test/atlas_web/live/demo_live_test.exs
```

The release test provisions and removes its own local PostgreSQL instance; it
never uses an existing database or managed cluster. It needs PostgreSQL binaries,
curl, and Python. Integration tests include a process-scoped telemetry probe for
unexpected writes during curated page loads and interactions, plus rejected
upstream HTTP calls.
