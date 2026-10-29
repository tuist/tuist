# Local tenant-isolation exercise

Use a **disposable local** PostgreSQL/ClickHouse pair, with no production
credentials or integrations. Never run this fixture against a shared environment.
It uses the test mail adapter, confirmed `example.invalid` users, and no billing
setup. It does not change DNS, providers, deployment configuration, or seed data
for any hosted environment.

## Automated regression

From `server/`, with the repository toolchains, PostgreSQL and ClickHouse running:

```sh
mise exec -- env MIX_ENV=test \
  TUIST_SERVER_TEST_POSTGRES_DB=tuist_tenant_isolation_test \
  TUIST_SERVER_TEST_CLICKHOUSE_DB=tuist_tenant_isolation_test \
  TUIST_SERVER_TEST_PORT=4199 TUIST_URL=http://127.0.0.1:4199 \
  mix test test/tuist_web/tenant_isolation_test.exs
```

Database names are overrides **after** `mise exec -- env`; Mise otherwise selects
the checkout's normal test databases. The test alias migrates them. Each test
rolls its fixture back. Use different database names/ports for parallel runs.
The local `TUIST_URL` also keeps SDK reporting away from the hosted service.

The regression exercises real bearer authentication and authorization with user
JWTs, project tokens, all-project account tokens and project-restricted account
tokens. It checks two populated private organizations in both directions:

- Bundle and test-run listings/details, and preview details, return the owning
  tenant's records only.
- Foreign project handles deny access (403); foreign child IDs under an allowed
  project return 404. Denied preview deletions leave the target row intact;
  corresponding authorized deletions succeed and remove their rows.
- Project credentials cannot widen to a sibling project; all-project account
  credentials can. Child-ID substitution must still match the URL's project,
  including for siblings in the same organization. Viewers/read-only tokens can
  read but cannot delete. Only an organization's admin can change project settings.
- Browser session mounts, connected bundle deletion, forged event identifiers,
  and viewer restrictions use the actual policy. Public project reads remain
  intentional and confer no write permission.
- Preview multipart signing/completion and icon signing reject foreign IDs
  before storage operations or metadata updates. Multipart checks cover both
  the legacy `preview_id` alias and the current `app_build_id`, including mixed
  own/foreign IDs to verify that the current field takes precedence. Only storage
  I/O is stubbed in these upload tests; authentication, policy and databases are real.

These are representative PostgreSQL and ClickHouse resource paths, not an
exhaustive endpoint audit. They do not establish artifact-download, cache-service,
MCP, SSO/OIDC, runner, provider, proxy, or deployed-environment isolation. Passing
locally is not independent external verification.

## Populate a disposable instance for a human

Use a separate pair of databases from automated tests so test resets cannot
destroy a review session. Do not load `test/test_helper.exs`: its sandbox owners
roll data back. These commands persist synthetic rows locally instead.

First create and migrate the dedicated local databases:

```sh
mise exec -- env MIX_ENV=test \
  TUIST_SERVER_TEST_POSTGRES_DB=tuist_tenant_retester \
  TUIST_SERVER_TEST_CLICKHOUSE_DB=tuist_tenant_retester \
  TUIST_SERVER_TEST_PORT=4199 TUIST_URL=http://127.0.0.1:4199 \
  bash mise/tasks/db/migrate.sh --create
```

Then open an interactive instance using exactly the same overrides:

```sh
mise exec -- env MIX_ENV=test \
  TUIST_SERVER_TEST_POSTGRES_DB=tuist_tenant_retester \
  TUIST_SERVER_TEST_CLICKHOUSE_DB=tuist_tenant_retester \
  TUIST_SERVER_TEST_PORT=4199 TUIST_URL=http://127.0.0.1:4199 \
  iex -S mix phx.server
```

Before provisioning, check the live repo configuration, then create the fixture:

```elixir
true = Mix.env() == :test
for repo <- [Tuist.Repo, Tuist.IngestRepo] do
  true = repo.config()[:hostname] in ["localhost", "127.0.0.1"]
  "tuist_tenant_retester" = repo.config()[:database]
end
password = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
tenants = TuistTestSupport.Fixtures.TenantIsolationFixtures.tenants_fixture("review", password: password)
```

Keep `password` and generated credentials private. Users are
`review-{alpha,beta}-{admin,user,viewer}@example.invalid`, all with that local
password. Each admin belongs only to its own organization; `user` has the member
role, and `viewer` has read-only membership. Neither tenant has ops privileges.
Each organization has private `ios-client` and `sibling` projects. `ios-client` has an
`alpha-app` or `beta-app` bundle with distinguishable size/file metadata, a private
preview, and a test run with tenant-specific module/case/scheme names. Previews
contain metadata only: no installable binary or object-storage content is seeded.

For API work, obtain a local user JWT and/or mint a restricted account token:

```elixir
{:ok, user_token, _} = Tuist.Guardian.encode_and_sign(tenants.alpha.user, %{}, token_type: "access_token")
project_token = tenants.alpha.project.token
{:ok, {_, restricted_token}} = Tuist.Accounts.create_account_token(%{
  account: tenants.alpha.organization.account,
  name: "local-review",
  scopes: ["project:bundles:read", "project:tests:read", "project:previews:write"],
  all_projects: false,
  project_ids: [tenants.alpha.project.id]
})
```

Use `Authorization: Bearer <local token>` against
`/api/projects/review-alpha/ios-client/bundles`, `/tests`, and their child-ID routes.
Record a successful own-tenant response first. Substitute `review-beta` with
`ios-client` unchanged, then substitute only `tenants.beta.bundle.id`,
`tenants.beta.test_run.id`, or `tenants.beta.preview.id` under alpha's corresponding
route. Repeat with beta's credentials.
For destructive controls, create a fresh disposable preview with
`TuistTestSupport.Fixtures.AppBuildsFixtures.preview_fixture(project: tenants.alpha.project)`;
delete it through the authorized API and confirm it is gone. Attempt the same
foreign-path and child-ID substitutions against beta's preview and confirm it
remains readable by beta. Save request/response evidence privately with the tested
revision, credential type/role, resource IDs, expected status and actual status;
never record raw passwords, bearer tokens, or confidential assessment material in
Git. Run the same comparisons in separate browser sessions using each role and
`/review-alpha/ios-client/bundles/<bundle ID>`.

Stop the instance after review. After rechecking the two exact disposable database
names, remove **only those local databases** using the same overrides and
`mix ecto.drop`; do not use the shared preview seeder or a shared reset task. No
procedure here authorizes preparing or deploying an external retest environment.
