# Luft server

Headless server at `https://luft.work` for Luft's native clients. It brokers Tuist OpenID Connect sign-in, issues Luft credentials and owns threads, lounges, DMs, runners, execution journals and conversation realtime in its own PostgreSQL database. Tuist owns accounts, organizations, provider credentials and sandbox infrastructure, exposed through scoped capabilities. `/` is a server-rendered homepage (`lib/luft_server_web/pages/home.html`, scripts disallowed), and the GPUI web edge (`../luft/gpui-web/`) runs under `/app/`; every other path stays headless. The standalone sources in `../luft/web/` remain outside this release and deployment.

## The contract

Standard protocols only, so either side can change implementation without the other:

| Step | Standard | Endpoint (on the Tuist server) |
| --- | --- | --- |
| Provider discovery | OpenID Connect Discovery 1.0 | `GET /.well-known/openid-configuration` |
| Sign in | OAuth 2.0 authorization code (RFC 6749) + PKCE S256 (RFC 7636), OpenID Connect Core 1.0 with `nonce` | `GET /oauth2/authorize` with the server's requested scopes |
| Sign up | Initiating User Registration via OpenID Connect 1.0 (`prompt=create`) | same |
| Code exchange | Confidential client, `client_secret_basic` | `POST /oauth2/token` |
| ID token | JWT signed RS256, keys as a JWK Set (RFC 7517) | `GET /oauth2/jwks` |
| Profile | OpenID Connect UserInfo | `GET /oauth2/userinfo` |
| Refresh / sign out | RFC 6749 section 6 (rotating) / RFC 7009 | `POST /oauth2/token`, `POST /oauth2/revoke` |
| Accounts and organizations | Bearer tokens (RFC 6750) on the Tuist REST API | `GET`/`POST /api/organizations` |

The ID token's `sub` is the Tuist user ID (stable); `preferred_username` is the personal account handle and `email`/`email_verified` the address. The Luft server's confidential client holds scoped Tuist credentials, encrypted in PostgreSQL sessions; it never returns those credentials to a native client or browser. Tuist's `Tuist.OAuth.Clients.luft_server_scopes/0` allows `openid profile email`, `account:organizations:write`, `luft:app`, `mcp`, `account:delete`, `account:members:read`, `account:sandboxes:write`, `account:repositories:read`/`account:repositories:write`, `project:admin:read` and `project:previews:read`/`project:previews:write`. Keep the requested scopes in `LuftServer.Tuist.OIDC` aligned with capabilities it needs. Existing sessions need another sign-in to obtain newly requested scopes.

### Native clients

Native clients default to `https://luft.work`. Desktop `LUFT_URL` overrides the saved startup origin; `TUIST_URL` does not configure native clients. A custom origin must be a Luft server exposing `GET /.well-known/luft.json` with `luft_oauth_client_id` equal to the fixed public native client ID `6653b77b-b787-4eb2-b955-8380ea5f1478`.

Boruta owns the downstream authorization-code, PKCE, access-grant and refresh lifecycle. Tuist authenticates the person; Luft creates its own 30-day session to hold encrypted upstream credentials. Boruta grants reference that session's UUID as their resource-owner subject, so separate sign-ins for the same person remain independent. The JWT serializer retains the user identity and account claims native clients display. Bearer authentication checks Boruta's stored grant and the live session; logout removes both the session and its grants and revokes its upstream refresh token, without clearing the person's Tuist browser session.

- `GET /oauth2/authorize`, `/oauth2/apple`, `/oauth2/google` and `/oauth2/github` start authorization-code sign-in with state and PKCE S256. Luft redirects through Tuist OIDC, where every sign-in requires explicit, CSRF-protected consent even when the person is already signed in to Tuist. Luft then returns a single-use code to exactly `luft://oauth-callback` or the desktop loopback URL `http://127.0.0.1:<port>/callback`.
- `POST /oauth2/token` exchanges that code and verifier, or rotates a refresh token. Luft issues a signed access JWT (`iss=luft`, native client audience), valid for up to one hour, and an opaque rotating `luft_refresh_…` token backed by a 30-day session. Clients send the access JWT as a bearer token; encrypted Tuist tokens stay on the server.
- Request objects (`request` and `request_uri`) are unsupported on native authorization and token endpoints and are rejected before Boruta parses them or makes HTTP requests. Both query and body parameter sources are checked.
- Retrying the immediately previous refresh credential within 60 seconds returns the same replacement token pair, including across replicas, so losing the first response does not sign the client out. A later rotation or logout ends that recovery window. Authorization codes remain strictly single-use.
- Each sign-in, sign-out, code exchange, refresh (including retries and reuse of a spent code or refresh token) and session revocation logs one line through `LuftServer.AuthEvents`: `auth_event`, `auth_outcome`, `auth_client`, `user_sub`, `session_id`, and the request's `client_address` (Cloudflare's `CF-Connecting-IP`, else the peer), `forwarded_for` and `user_agent`. Lines go to stdout, which the cluster's log collector ships to Pulse; they never carry tokens, codes or verifiers. Find a session's history with `auth_event=` and its `session_id`.
- The API serves `/api/accounts/:account_handle/threads` and `/lounges` locally. `/threads/socket/websocket` terminates in Luft, including inbox and presence channels. `/api/me/ai-subscriptions` (list, `PUT /claude`, `POST /chatgpt/login`, `POST /chatgpt/login/poll`, `DELETE /chatgpt/login`, `DELETE /:provider`) is served by `LuftServer.AISubscriptions`, which keeps the credentials encrypted under a key derived from `SECRET_KEY_BASE` and runs ChatGPT inference against OpenAI's Codex backend directly; ChatGPT sign-in needs `LUFT_CHATGPT_CLIENT_ID`. Each change that succeeds is broadcast to the person's `ai_subscriptions` channel on the same socket. MCP servers live in `LuftServer.MCPServers`: a person's own under `/api/me/mcp-servers` and an organization's under `/api/accounts/:account_handle/mcp-servers`, which every member lists and only admins change. Their OAuth sign-in returns to `/mcp-servers/callback`, which hands the answer to `luft://mcp-callback` for the app to complete with its bearer, and every request to an MCP or authorization server goes over a pinned, SSRF-guarded connection. Discovery drops each tool that breaks a rule and logs the rule. Only identity/organization, preview/project, account deletion and generic device-transport requests go upstream.
- Local runner registration returns a `luft_runner_local_…` credential once, stores only its SHA-256 hash, and binds it to the exact Luft session. Logout, expiry and revocation invalidate it. Legacy encrypted upstream wrappers remain recognizable but are not newly issued. Preview links and media use the Luft origin; object-storage URLs remain unchanged.

### Conversation authority and cutover

Threads run on the owner's ChatGPT subscription and offer the originating author's own MCP servers and the thread account's. Execution reloads Tuist authorization; it never chooses another sign-in for the same person. Tuist's built-in MCP tools, workspace/repository and notification APIs retain upstream secrets without owning conversations. Shipping persists reviewed consent before dispatch; an uncertain publication is reconciled by observation, never retried as a new write.

Luft supervises its durable agent hosts and uses Oban for recovery, shipping, timed snooze and notification jobs. Production replicas require the chart's dedicated distribution cookie and DNS clustering configuration. Keep `SECRET_KEY_BASE` stable and identical across replicas: it protects sessions, checkpoints, results and journal objects. The image includes the trusted native card kit, checksum-pinned NSH compiler and muontrap; it contains no browser frontend.

Follow [the offline cutover runbook](docs/conversation-cutover.md) before switching historical traffic. The import preserves IDs/history, re-encrypts private state and deliberately clears historical execution delegation. An owner can explicitly bind an idle thread to the current sign-in with `POST /api/accounts/:account_handle/threads/:id/reauthorize`. Imported unfinished work must first be archived/cancelled and restored; reauthorization never revives old commands or shipping consent. Historical source tables and objects remain retained until separately approved retirement. Tuist account/user deletion does not cascade into this separate database; operators must coordinate erasure and legal exports across both stores before production cutover.

Boruta uses its upstream Ecto adapters with PostgreSQL-authoritative reads. `NativeAuth.exchange/1` locks the owning session and commits Boruta's writes with the encrypted retry response in one transaction. Keep those locks: the adapters' check-then-revoke flow alone does not serialize concurrent code redemption or refresh rotation. New Boruta releases may require more generated migrations (`mix boruta.gen.migration`). Apply the generated migrations and `20261119190200_configure_luft_oauth_grants` before starting this version. The former custom native credentials do not have Boruta grants and require a fresh sign-in; browser-cookie sessions remain valid.

Take a database backup before this schema upgrade. A full schema downgrade is not supported by the upstream migration chain: `ClientsSignaturesAdapters`, for example, cannot reverse its column alterations. Prefer a forward fix or restore a pre-upgrade backup with writers stopped. The Luft-specific grant migration does have a rollback, which deletes native grants rather than truncating JWTs and therefore requires another sign-in; it does not make the upstream migrations reversible.

### Retained browser cookie flow

The existing browser flow remains available without a deployed frontend. It uses the same-origin session cookie (`__Host-Http-luft_session`, `HttpOnly`, `Secure`, `SameSite=Strict`):

- `GET /auth/login?return_to=<path>[&signup=1]`: starts signing in (or up) with Tuist, then lands on `return_to` (a local path, default `/`).
- `GET /auth/callback`: the OAuth redirect URI.
- `POST /auth/logout`: ends the session and revokes Tuist's refresh token.
- `GET /api/me`: `{id, handle, email}`.
- `GET /api/organizations`: the person's Tuist organizations; `POST /api/organizations` `{name}` creates one in Tuist.

Cookie-authenticated writes must carry this origin's `Origin` header. Native bearer requests use Luft access JWTs.

Unauthenticated API calls answer `401 {"error": "unauthenticated", "login_url": ...}`.

## Configuration

Tuist server (the deployment Luft signs in to), all required for it to act as the OpenID Provider. In production the Tuist chart's `server.config.luftServerOidc` syncs them: the signing key from the `OIDC_PROVIDER` 1Password item (`signing-key.pem`), the client ID and secret from the `LUFT_SERVER` item this server's chart also reads, and the redirect URIs from the chart's values.

- `TUIST_OIDC_SIGNING_KEY`: RSA private key (PEM) that signs ID tokens. It may hold several concatenated PEM blocks: the first signs, and `/oauth2/jwks` publishes all of them, so a key can be published before it signs and kept while its tokens are live. `Tuist.Environment.oidc_signing_keys/1` has the rotation steps.
- `TUIST_LUFT_SERVER_OAUTH_CLIENT_ID` (a UUID) and `TUIST_LUFT_SERVER_OAUTH_CLIENT_SECRET`.
- `TUIST_LUFT_SERVER_OAUTH_REDIRECT_URIS`: `https://luft.work/auth/callback` (comma-separated, exact).

This server (`config/runtime.exs`): `DATABASE_URL`, `SECRET_KEY_BASE`, `LUFT_SERVER_OAUTH_CLIENT_ID`, `LUFT_SERVER_OAUTH_CLIENT_SECRET`, and optionally `TUIST_URL` (default `https://tuist.dev`), `PUBLIC_URL` (default `https://luft.work`), the origin people see, and `LUFT_CHATGPT_CLIENT_ID`, the public OAuth client for ChatGPT subscription sign-in (the chart's `chatgptClient`).

## Local development

### Opt-in Thread record references

This integration opens records from an already published **local, disposable** workspace, not a production database. It is disabled when `:record_workspaces` is absent (the default). It does not provision databases or infer business permissions from organization membership, account administration, thread readership or the author's grants. The standalone local preview API is unchanged.

An operator may set this trusted Elixir application configuration in the server's runtime configuration:

```elixir
config :luft_server, :record_workspaces, %{
  # {verified Tuist organization ID, verified Tuist account ID}; never handles
  {10, 100} => %{
    database: "luft_workspace_demo",
    organization: "demo", # exact installed workspace_catalog.definition.organization
    users: %{
      # verified Tuist user ID => explicit operation names (no wildcard/inheritance)
      42 => %{
        queries: ["support.conversation.get", "support.conversation.list", "accounts.customer.get"],
        actions: ["support.conversation.update"]
      },
      43 => %{queries: ["support.conversation.get"], actions: []}
    }
  }
}
```

Operation IDs must match the installed catalog; the example uses the local Support and Account Management apps. The installation must have exactly one entry module for the reference's model, with a declared, granted `get` query for that model. Runtime sources must be nonempty and at most 256 KiB, workspace titles at most 200 bytes, and there must be 1–20 modules. Module operations must target the module's own model, except declared getters of its reference-field targets. PostgreSQL remains restricted to loopback and `luft_workspace_*` databases through `Workspaces.Local`; connection settings are the existing trusted `LUFT_WORKSPACE_PGHOST/PGPORT/PGUSER/PGPASSWORD` settings, not HTTP input. No installation, publication or grant-management HTTP API is added. Apply configuration consistently on every replica before opting in; removing a user/operation takes effect on the next request on each replica. This is operation-level authorization, not row-level or field-level policy. A query grant permits that query's bounded results across its model.

Apply `20261123000000_add_record_references` before starting the new writers. `thread_messages.record_reference` is nullable JSONB `{model, id}`, with `kind = "record"` and body `Open record`; it contains no title, business row, source, credentials or permission snapshot. Thread serialization adds `record_reference` to the assistant message. Existing messages are unchanged. To roll back, stop new writers first; preserve/export reference messages before reversing the additive migration, since dropping the column discards those references.

Authenticated endpoints (native bearer or same-origin session cookie; cookie POSTs require the usual `Origin` header):

- `GET /api/accounts/:account_handle/threads/:id/records/:message_id` has no input body. It returns `{workspace, module, reference: {model, id}}` only after fresh upstream scope/thread access, installation/grants, module/getter availability and target existence checks. `workspace` retains the complete catalog envelope and dependency model schemas, but omits unreadable modules and their sources and filters query/action definitions and capability lists to explicit user grants. Clients must perform a fresh canonical getter through `/query` to load current rows. The reference message must belong to this exact thread; a row UUID or another thread's message cannot substitute for it.
- `POST .../records/:message_id/query` accepts only `{module, query, input}`. `input` is the existing closed Local query input: `{}` for `list` (at most 100 rows), or `{id}` for `get`. Returns the existing `{items: [...]}` or `{record: ...}` result. An independent linked-customer getter requires both a module declaration and its own explicit user query grant, even when Support is readable. An allowed missing linked record returns 404 without invalidating the Support reference.
- `POST .../records/:message_id/action` accepts only `{module, action, request_id, input}`. `request_id` is a client UUID, reused unchanged when retrying. Existing Local closed inputs apply: create `{values}` or update `{id, expected_revision, values}`. Returns the existing record result. Referenced models in supplied write values additionally require an independent `get` grant. Durable replay and optimistic revisions are unchanged, but request IDs are server-namespaced by account/user/thread/reference message so one caller cannot retrieve another caller's cached result. Current thread access, getter, module declaration, operation grant and linked-target grants are checked before every execution **and replay**. A completed action has exactly one workspace audit row.

For both POSTs `module` must equal the entry module resolved by the server from the persisted reference. Bodies never accept a database, organization, actor, token, URL or grants. Generated `show_ui` card JavaScript gains no workspace access.

All record responses use `Cache-Control: no-store`. Errors use the Local preview envelope `{error: {code, message: "Record unavailable"}}`: 403 `FORBIDDEN` for any upstream/thread/installation/grant/module denial (clients must clear cached sources, rows and pending writes), 404 `NOT_FOUND` for an absent reference message or an authorized missing row, 409 `REVISION_CONFLICT` for stale writes or conflicting request reuse, 422 `VALIDATION_FAILED` for invalid field values or missing linked write targets, and 422 `INVALID_REQUEST` for invalid closed business input. Workspace database/transport faults and upstream context unavailability return 503 `UNAVAILABLE`, without exception text: the outcome may be unknown, including at commit, so clients must preserve the pending request UUID for a deliberate retry. The server never automatically retries mutations. Error messages never echo submitted values. The existing authentication plug still returns its normal 401 for invalid/expired Luft credentials. Upstream authorization refusals fail closed as 403 here; an unavailable authorization service is not represented as permission revocation.

Actual Thread hosts offer replay-safe `workspace_queries` (up to 100 permitted query descriptors), `query_workspace` (closed module/query/input; at most 100 rows), and `show_record` (closed `{model,id}`). They use the live run attempt, the exact triggering human message's author session, fresh upstream scope/thread access and that author's current grants, not the paying owner's grants. `show_record` checks the current getter/target before appending and deduplicates the same reference within the run. Each reader later opens current state under their own grants. Query results may enter the encrypted agent journal, like other authorized tool results; the shared reference message itself stores no row data.

```sh
# Tuist server with the Luft server client (from server/)
openssl genrsa -out /tmp/oidc.pem 2048
TUIST_OIDC_SIGNING_KEY="$(cat /tmp/oidc.pem)" \
TUIST_LUFT_SERVER_OAUTH_CLIENT_ID=0b2f5c0e-7a3d-4c6e-9a51-2d4f8e1b6c37 \
TUIST_LUFT_SERVER_OAUTH_CLIENT_SECRET=local-dev-secret \
TUIST_LUFT_SERVER_OAUTH_REDIRECT_URIS=http://localhost:4200/auth/callback \
mise run dev

# This headless server (from luft-server/), on http://localhost:4200
mise install && mix setup
TUIST_URL=http://localhost:8080 \
LUFT_SERVER_OAUTH_CLIENT_ID=0b2f5c0e-7a3d-4c6e-9a51-2d4f8e1b6c37 \
LUFT_SERVER_OAUTH_CLIENT_SECRET=local-dev-secret \
mix phx.server
```

`mix phx.server` starts only Phoenix, with no web watcher. Use `http://localhost:4200` as a native development origin (desktop: `LUFT_URL=http://localhost:4200`); HTTP is for loopback development only. The Tuist seed login is `tuistrocks@tuist.dev` / `tuistrocks`. The retained `/auth/login` flow ends at a JSON 404 if its `return_to` has no API route; there is no landing page.

### Opt-in reviewed JavaScript behaviors

The next foundation slice uses `:behavior_workspaces`, not the earlier NSH
`:record_workspaces` catalog. It is disabled by default and remains a **local,
disposable rehearsal**, not a production tenancy or data-lifecycle solution.
Configure `{organization_id, account_id} => "luft_workspace_example"`; the IDs
come from fresh upstream authorization, never client input. Existing PostgreSQL
loopback/database-name restrictions still apply. Do not bind both runtimes to
the same scope/database.

`priv/behaviors/support.json` is the portable definition: typed customer/support
resources, explicitly projected fields, searchable/filterable/sortable lists,
owner-approved cross-resource exports and JavaScript methods with closed input
schemas. UI clients receive descriptors and records, never executable UI code.
Native clients use the shell's navigation stack for conversation → record →
related customer → Back. Profile → Collections offers lists, search, enum
filters, sort and method forms. The earlier preview remains separate.

Provision with `mix luft.behavior.init --database luft_workspace_example
--organization 10 --account 100 --principals /path/to/principals.json`.
The trusted principals file maps verified user IDs to explicit `roles`
(`author`, `approve`, `merge`, `activate`), `owners` (namespace names), `collections`
(resource IDs) and `methods` (method IDs). Provisioning neither approves nor
activates anything. Keep this file outside source control.

#### Organization ops repositories

Each organization has one private **ops repository** for its authored
resources, behaviors and workflows. Its project repositories are separate;
this mapping neither limits their number nor grants access to them. The central
Luft database stores only the scalar Tuist organization ID and an opaque UUID
in `organization_ops_repositories`. Accounts within that organization
share the repository but retain separate installations, grants and release refs.
Resource records, invocation results and grants remain in PostgreSQL, not Git.

Apply `20261126000000_create_organization_ops_repositories` to the Luft
database. Rerun the trusted initializer for each existing behavior database to
add its nullable commit/review/merge columns; it preserves releases and resource rows.
The initializer does not infer a `merge` grant from an existing activation grant.
Set `LUFT_GIT_ENDPOINT=host:port` to the private Git gRPC endpoint. Provisioning
is lazy, after verified Tuist scope, installation binding and author grants;
there is no public raw-Git, repository-selection or credential endpoint. The Git
service itself does not isolate tenants: it must stay private and reachable only
by trusted services. Production enablement also needs the corresponding network
policy; this change does not configure or deploy it.

Proposals fork the observed `refs/heads/main` into
`refs/heads/releases/<account_id>/<hash>` and write only
`accounts/<account_id>/release.json`. The envelope contains the complete
definition, runtime, active baseline, organization/account, release hash and
reviewed Git base (`base_commit_id`, null for an empty repository). Account
paths preserve the other accounts' definitions in the same ops repository.
The release hash binds that base: after main moves, reproposing produces a new
commit/hash requiring fresh review. Saved repository/commit/base pins never
follow a moving proposal branch.

Approval verifies the exact Git envelope and rechecks independent reviewer
grants. **Merge** requires a separate `merge` grant, current reviewer authority,
an unchanged active baseline and an additive contract. It fast-forwards main
to the exact reviewed commit using ancestry checks and compare-and-swap; a
stale base or a rejected ref update returns 409, never an automatic rebase or
force push. Main is approved desired configuration, not the running version.
Merge does not install resource tables, run JavaScript or activate anything.

**Activation** requires a confirmed merge, an `activate` grant and a still-valid
review. It verifies that the reviewed commit remains in main's history and the
account's envelope at main still matches it. A later merge by another account
does not prevent activation. Resource installation and active-pointer changes
remain in the local PostgreSQL transaction. This slice allows one unactivated
merge per account: activate or reconcile it before proposing another change.

Before attempting the Git write, Luft commits a merge intent and actor/event.
An interrupted write remains `merging`; it is not automatically retried or
reported as merged. Inspect the release, then deliberately retry that hash's
merge to reconcile the pinned commit. A successful retry records one confirmed
merge without appending another Git commit. Review changes are frozen while
merging. A known CAS/base rejection becomes `merge_conflict` and permits a new
proposal and review. Already confirmed merges remain distinct from activation.

Missing/unreachable Git fails proposal, approval, merge and activation closed; existing
active resource operations remain local. A failed request can leave an inert
repository mapping or Git proposal: retry the same content/baseline to reconcile
it, never assume an unavailable response means nothing was written. Git-backed
hashes include a storage-format marker, so legacy proposals without the reviewed main base cannot
inherit approval. Repropose their definition and obtain a new review; already
active legacy releases keep running. There is no automatic Git erasure or
upstream deletion propagation; the rehearsal remains disabled for customer data.

The vendored protobufs in `priv/git/proto/enroute/` are from Enroute v0.4.1
(`proto/enroute/` in the upstream release source), under `priv/git/LICENSE`.
The generated client modules are internal implementation details under
`LuftServer.Git.Enroute`. To regenerate, install `protoc` and the locked Protobuf
Elixir generator, then use `-I priv/git/proto` and
`--elixir_out=plugins=grpc,package_prefix=LuftServer.Git:lib` for
`common/v1alpha1/common.proto` and `api/v1alpha1/{repository,commit,object,ref}.proto`
under `priv/git/proto/enroute/`; keep generated files in the matching
`lib/luft_server/git/enroute/` namespace directory.

Authenticated endpoints under `/api/accounts/:account_handle`:

- `GET /behaviors` returns the active authoring definition, schema, runtime and
  constraints to an author. `POST /releases/validate` (`{definition, baseline}`)
  checks the bounded contract and compiles methods without executing them or
  persisting anything. It returns repair diagnostics and additive compatibility;
  valid compilation is not proof of business behavior.
- `GET /releases` lists the latest 20 metadata entries; `GET /releases/:hash`
  returns the exact candidate, baseline, JSON-pointer changes, current reviewer
  authority and action blockers. `POST /releases` (`{definition, baseline}`)
  freezes an immutable candidate. The hash binds its exact definition, baseline,
  account/organization, Git main base, storage format and Javex/provider identity.
  Responses expose `repository_key`, `commit_id`, `base_commit_id` and, after
  approval, `reviewed_commit_id`. Identical proposals against the same main reuse
  one release and one proposed event; they never edit the existing candidate.
- `POST /releases/:hash/approve` requires an independent, owner-authorized
  reviewer; `POST /releases/:hash/merge` updates ops/main without activation.
  `POST /releases/:hash/activate` requires that confirmed merge and rechecks
  reviewer authority, baseline and main membership. Only additive upgrades
  merge or activate; breaking contracts remain reviewable but blocked.
  Release detail exposes `can_merge`, `merge_blockers`, `merged_at`, `merged_by`
  and `merge_requested_by`, with `merging`, `merge_conflict` and `merged` states
  in addition to the existing lifecycle. `merged` means awaiting activation.
- `GET /collections`, `POST /collections/:collection/query` (bounded search,
  filters, sort, offset/limit) and `GET /collections/:collection/records/:id`
  expose only current grants/projections. `?version=N` reads an immutable
  snapshot without method actions.
- `POST /methods/:method` takes `{request_id, input}`. The request UUID is scoped
  to its principal; exact replay returns the saved result only after fresh
  authorization. Conflicting input or stale revisions fail rather than retry.
- `GET /threads/:id/resources/:message_id` resolves a persisted opaque reference
  after both thread and resource authorization. Session discovery/query tools
  return locators, not projected field values, to avoid copying protected rows
  into a shared journal. The reader resolves current state with their own grants.

Session agents use `inspect_behaviors`, `validate_behavior_release`,
`propose_behavior_release`, `inspect_behavior_releases`, `merge_behavior_release` and
`promote_behavior_release`. Each call checks the live run/lease and the exact
triggering human's current sign-in, thread access and installation grants, not
the subscription owner's permissions. Authoring inputs and definitions become
conversation/journal content: never embed secrets or resource snapshots in them.
There is no approval tool. Merge and promotion require separate explicit requests
and grants. Promotion uses an independently approved, merged hash and the author's
activation role. An uncertain mutation result is not
automatically replayed; inspect the current release before acting again.

Apple's Profile → Releases uses the existing native navigation stack. Reviewers
can inspect exact changes and full definitions, approve a candidate, merge it
into main without activation, then separately activate that hash. Rust owns validation, authority, action selection
and HTTP. Profile changes, backgrounding and failed requests clear review
authority; actions never enter the offline outbox. The server rechecks every
permission, baseline and runtime at the actual write, even after a displayed
capability said it was available.

Linux runs Javex's isolated backend with bounded concurrency, fuel, memory,
deadlines and callback counts. Only generic `resources.get/create/update` are
available; methods cannot access HTTP, filesystem or credentials. One mutation
per invocation commits with its immutable version, result and event in a single
serializable PostgreSQL transaction. No automatic mutation retry occurs.

This slice does **not** provide production erasure/retention, general migrations,
separate installed behavior-instance identities, workflows/external effects,
an app directory, durable mutable drafts or integration bindings. Validation is
compile-only, and no live-model authoring quality is established by the tool
contract. See `../server/data-export.md` for the
additional rehearsal storage and export requirements before production use.

## Release image

The image contains the Elixir release, database migrations, the native card compiler/kit and the GPUI web edge. A `luft-web` stage compiles `luft-gpui-web` to wasm with Luft's pinned Rust and wasm-bindgen, without Struo or Node, and the release serves the output from `priv/static/app`: `/app` redirects to `/app/`, `/app/` and its client-side paths return the page, and only `main.js`, `luft_gpui_web.js` and `luft_gpui_web_bg.wasm` (gzip-compressed when accepted) are served as files, under a content security policy for that app alone. Unmatched paths return JSON 404s, including `/index.html`, `/assets/*` and other files under `/app/`. `.github/workflows/luft-server-deployment.yml` also redeploys when the Luft sources this build reads change. Build from the repository root:

```sh
docker build -f luft-server/Dockerfile .
```
