# Migrating server secrets from the encrypted blob to 1Password

This runbook moves every still-used server secret out of the encrypted
`server/priv/secrets/<env>.yml.enc` blob and into per-env 1Password vaults,
synced into the cluster by External Secrets Operator (ESO). Once it is done the
blob, `MASTER_KEY`, and the decrypt path are removed entirely.

The chart side is already wired: a single ExternalSecret
(`templates/server-config-external-secrets.yaml`) reads the per-concern 1P
items below into one Secret whose keys are `TUIST_*` env var names, mounted into
the Server / Migration / Processor pods via `envFrom`. It is gated on
`server.config.managedSecrets` and is **off by default** — flip it on per env
only after that vault is fully populated.

## What moves, what's already in 1P, what's dropped

Decided after auditing every `Tuist.Environment` accessor and its call sites.

### Migrated to 1Password (per-env vault) — 12 new items

| 1P item | Fields (label → env var) | Blob source |
|---|---|---|
| `SENTRY` | `dsn` → `TUIST_SENTRY_DSN` | `sentry.dsn` |
| `STRIPE` | `publishable_key`, `secret_key`, `endpoint_secret` → `TUIST_STRIPE_*` | `stripe.publishable_key/secret_key/endpoint_secret` (the price IDs are **not** secrets — they live in the chart, see below) |
| `SLACK` | `client_id`, `client_secret`, `tuist_token` → `TUIST_SLACK_CLIENT_ID/CLIENT_SECRET/TUIST_TOKEN` | `slack.client_id`, `slack.client_secret`, `slack.tuist.token` |
| `APPLE` | `app_client_id`, `service_client_id`, `team_id`, `private_key_id`, `private_key` → `TUIST_APPLE_*` | `apple.*` |
| `OAUTH` | `client_id`, `client_secret`, `jwt_public_key` → `TUIST_OAUTH_*` | `oauth.client_id/client_secret/jwt_public_key` (see ⚠️ below) |
| `MAILGUN` | `api_key` → `TUIST_MAILGUN_API_KEY` | `mailgun.api_key` (the mailing domain/from/reply-to are not secrets — they live in the chart under `server.mailing`, see below) |
| `POSTHOG` | `api_key`, `url` → `TUIST_POSTHOG_API_KEY/URL` | `posthog.*` |
| `LOOPS` | `api_key` → `TUIST_LOOPS_API_KEY` | `loops.api_key` |
| `CLICKHOUSE` | `url` → `TUIST_CLICKHOUSE_URL` | `clickhouse.url` |
| `PLAIN` | `authentication_secret` → `TUIST_PLAIN_AUTHENTICATION_SECRET` | `plain.authentication_secret` |
| `CACHE_API_KEY` | `password` → `TUIST_CACHE_API_KEY` | `cache_api_key` |
| `SECRET_KEYS` | `base`, `password`, `tokens`, `encryption` → `TUIST_SECRET_KEY_*` | `secret_key.*` |

> ⚠️ **`SECRET_KEYS` is the dangerous one.** `encryption` is the Cloak key for
> encrypted DB columns (accounts/projects/orgs/webhook signing secrets/Slack
> URLs/GHES installs), `tokens` signs Guardian JWTs, `password` salts password
> hashes + SCIM/agent/API tokens, and `base` signs Phoenix sessions. They
> **must** carry the exact current values. Today `base` comes from the blob in
> managed envs (the chart's `TUIST_SECRET_KEY_BASE` is gated behind
> `not managedSecrets`), and `password`/`tokens`/`encryption` fall back to
> `base` only if unset — so a wrong/missing value rotates them and breaks live
> data and sessions.

> ⚠️ **`OAUTH` — only three fields, and a latent bug to note.** The blob's
> `oauth` block is `client_id`, `client_secret`, `jwt_public_key`,
> `jwt_private_key`. But `Tuist.OAuth.Clients` reads `oauth_private_key`
> (`[:oauth, :private_key]`) and `oauth_client_name` (`[:oauth, :client_name]`)
> — neither of which the blob sets — so in prod today the seeded OIDC client
> has `private_key: nil` and `name: nil`, and the blob's `jwt_private_key` is
> read by nothing. To preserve current behavior, sync only `client_id`,
> `client_secret`, `jwt_public_key`; do **not** add `client_name` or
> `private_key` (an empty `TUIST_OAUTH_PRIVATE_KEY` would crash
> `JOSE.JWK.from_pem/1` in `to_client_jwk/1` — strictly worse than unset).
> Separately: `oauth_private_key` reading `private_key` instead of the blob's
> `jwt_private_key` looks like a pre-existing wiring bug (the OIDC client's
> RS256 signing key is effectively unset). Fix it as its own change if RS256
> ID-token signing is meant to be on — not silently as part of this migration.

### Already in 1Password (no new item; just confirm each vault has it)

`MASTER_KEY`, `GITHUB_APP` + `GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES` +
`GITHUB_TOKEN_UPDATE_PACKAGES`, `GOOGLE_OAUTH`, `S3_CREDENTIALS`,
`WEB_/PROCESSOR_/OPS_DATABASE_PASSWORD`, `S3_BACKUP_CREDENTIALS`, the Kura
items. The license moves onto the existing ESO path: add a `TUIST_LICENSE_KEY`
item (field `password`) to each managed vault (preview envs already use it).

### Dropped as dead-weight (no consumer; not migrated, removed with the blob)

`mautic`, `app_signal`, `better_stack`, `bugsnag` (legacy error tracking —
Sentry now), `ops_user_handles` (replaced by the `@tuist.dev` + Google
heuristic), `xcode_processor.*` (the build/xcresult processors are the same
image via `TUIST_MODE`, no separate URL/secret), `stripe.prices` (not secret —
moved to the chart, see below), `database_url` +
`ipv4_database_url` (managed envs are on CNPG — `DATABASE_URL` comes from the
CNPG role Secret), `anthropic.api_key` + `openai.api_key` (no call sites;
LangChain is a dep but never instantiated — re-add when an LLM feature lands),
`additional_finch_pools` (decoded to a connection pool for
`https://s3.us-west-2.amazonaws.com` — a pre-Tigris AWS S3 endpoint the app no
longer calls, so Finch never matches it; the env-var *mechanism* stays, only
this stale value is dropped),
`oauth.jwt_private_key` (no reader — see the OAUTH ⚠️ above), and `namespace.*`
(the Namespace runner integration was retired — provisioning was already dead;
the `Tuist.Namespace` module, the `.well-known/openid-configuration` + `jwks.json`
endpoints it backed, the usage-meter call, and the `Account.namespace_tenant_id`
schema field were removed, and the DB column is dropped by migration
`20260623120000_drop_namespace_tenant_id_from_accounts`).

## Step 1 — Read the current values

You hold the master key, so decrypt each env's blob to copy values out. From
`server/`:

```bash
# Opens the decrypted YAML in $EDITOR (uses priv/secrets/<env>.key or MASTER_KEY).
mix secrets.edit prod   # then stag, then can
```

The Stripe **price IDs** are not secrets and are not part of this — they live in
the chart under `server.stripe.prices` (production + staging are filled in their
overlays; add canary's own test-mode IDs to its overlay). Only the Stripe API
keys (`secret_key`, `endpoint_secret`, `publishable_key`) go into the `STRIPE`
1P item.

Likewise the **mailing identity** (`domain`, `from_address`, `reply_to_address`)
is not secret — it's set once in `values-managed-common.yaml` under
`server.mailing` (shared across envs: `mail.tuist.dev` / `noreply@tuist.dev` /
`contact@tuist.dev`). Only the Mailgun `api_key` goes into the `MAILGUN` 1P item.

## Step 2 — Create the items in each vault

Vaults: `tuist-k8s-production` (most important), `tuist-k8s-staging`,
`tuist-k8s-canary`. Run the block once per vault — set `VAULT` and re-run.
`[password]` keeps the value concealed in the 1P UI; `[text]` is for plain
single-line values. Multi-line keys (Apple/OAuth/Namespace) are stored as
`[file]` attachments — ESO reads them by filename, so the attachment name must
match the chart's remoteRef (`private-key.pem`, `jwt-public-key.pem`,
`ssh-private-key`).

```bash
op signin   # if needed
VAULT=tuist-k8s-production

op item create --vault "$VAULT" --category "API Credential" --title SENTRY \
  'dsn[password]=<sentry.dsn>'

op item create --vault "$VAULT" --category "API Credential" --title STRIPE \
  'publishable_key[password]=<stripe.publishable_key>' \
  'secret_key[password]=<stripe.secret_key>' \
  'endpoint_secret[password]=<stripe.endpoint_secret>'

op item create --vault "$VAULT" --category "API Credential" --title SLACK \
  'client_id[password]=<slack.client_id>' \
  'client_secret[password]=<slack.client_secret>' \
  'tuist_token[password]=<slack.tuist.token>'

# Multi-line keys are 1Password FILE ATTACHMENTS (`[file]=`), not text fields —
# ESO reads them by filename. Save each from the decrypted blob to the path
# below first; the attachment filename must match the remoteRef in the chart.
op item create --vault "$VAULT" --category "API Credential" --title APPLE \
  'app_client_id[text]=<apple.app_client_id>' \
  'service_client_id[text]=<apple.service_client_id>' \
  'team_id[text]=<apple.team_id>' \
  'private_key_id[password]=<apple.private_key_id>' \
  'private-key.pem[file]=./apple_private_key.pem'      # ← apple.private_key

# OAuth: client_id (OIDC client UUID, not secret) + secret + public key file.
# See ⚠️ above — client_name/private_key stay unset.
op item create --vault "$VAULT" --category "API Credential" --title OAUTH \
  'client_id[text]=<oauth.client_id>' \
  'client_secret[password]=<oauth.client_secret>' \
  'jwt-public-key.pem[file]=./oauth_jwt_public_key.pem'  # ← oauth.jwt_public_key

op item create --vault "$VAULT" --category "API Credential" --title MAILGUN \
  'api_key[password]=<mailgun.api_key>'

op item create --vault "$VAULT" --category "API Credential" --title POSTHOG \
  'api_key[password]=<posthog.api_key>' \
  'url[text]=<posthog.url>'

op item create --vault "$VAULT" --category "API Credential" --title LOOPS \
  'api_key[password]=<loops.api_key>'

op item create --vault "$VAULT" --category "API Credential" --title CLICKHOUSE \
  'url[password]=<clickhouse.url>'

op item create --vault "$VAULT" --category "API Credential" --title PLAIN \
  'authentication_secret[password]=<plain.authentication_secret>'

op item create --vault "$VAULT" --category Password --title CACHE_API_KEY \
  'password=<cache_api_key>'

op item create --vault "$VAULT" --category "API Credential" --title SECRET_KEYS \
  'base[password]=<secret_key.base>' \
  'password[password]=<secret_key.password>' \
  'tokens[password]=<secret_key.tokens>' \
  'encryption[password]=<secret_key.encryption>'

# License onto the existing ESO path (skip if the vault already has it).
op item create --vault "$VAULT" --category Password --title TUIST_LICENSE_KEY \
  'password=<license>'
```

> Every field referenced by the ExternalSecret must exist in every vault ESO
> reads — a missing item/field fails the **whole** sync for that env (and wedges
> the deploy on the migration-job hook). For a concern an env genuinely doesn't
> use, **don't** sync an empty string — gate it out instead, so its keys aren't
> referenced at all. PostHog already works this way: `server.config.posthog.enabled`
> (default true) is set `false` in `values-managed-canary.yaml` because canary has
> no `POSTHOG` item. (Empty string is especially wrong for PostHog — the analytics
> gate is `!= nil`, so `""` would switch analytics on with empty creds.) Same
> pattern if another env turns out to lack Slack/Loops/Plain/etc.

## Step 3 — Dev (1Password `Development` vault, via fnox)

Local dev no longer uses an encrypted blob. `server/fnox.toml` references the
dev secrets (in the `Development` vault), and `mise run dev` / `mise run db:seed`
inject them with `fnox exec` when 1Password access is present (contributors
without it boot plain — `fnox.toml` sets `if_missing = "warn"`, so a missing
item just disables that integration locally instead of failing). The exact
items + field labels fnox expects are listed in `server/fnox.toml`.

Dev runs **unhosted** (`TUIST_HOSTED=0`), so there is no dev license — the
Keygen check is skipped and the decrypted dev blob never carried one.

First-party devs: `mise install` (pulls fnox) + an `op signin` session or an
`OP_SERVICE_ACCOUNT_TOKEN` scoped to `Development`. Add more dev secrets by
adding entries to `server/fnox.toml` (and the matching `Development` item).

## Step 4 — Cut over (per env, staging → canary → production)

The cutover is **already applied** in `values-managed-common.yaml`
(`server.config.managedSecrets: true` + `server.externalSecrets.license.item:
TUIST_LICENSE_KEY`), so merging + deploying this branch performs it — which is
why all three managed vaults must be populated first (they are).

Deploying syncs the consolidated config Secret and sources the license from 1P;
the encrypted blob + `MASTER_KEY` stay in place as a safety net (env vars
override the blob, so values are identical, just env-sourced now). The
migration-job hook waits for the ExternalSecret's Ready condition, so a
missing/incomplete vault fails the deploy at the hook rather than booting a
half-configured release. The normal `main` cascade (canary → acceptance tests →
production) validates each env in turn.

### Verify before removing the blob

- ExternalSecret synced: `kubectl --context tuist-k8s-<env> -n tuist get externalsecret` (all `SecretSynced=True`).
- Pods healthy, `/ready` green, no boot errors.
- Spot-check behavior that depends on the migrated keys: a login (OAuth/OIDC),
  a Stripe call, a Sentry event, and — critically — that **existing**
  Cloak-encrypted columns still decrypt and existing sessions/tokens still work
  (confirms `SECRET_KEYS` carried the exact values).

## Step 5 — Remove the blob

**Done in this PR** (the blob is no longer baked, read, or needed):

- Deleted `server/priv/secrets/{prod,stag,can,dev}.yml.enc` (kept the plain
  `test.yml` fixture for tests).
- `server/lib/tuist/environment.ex`: `decrypt_secrets/0` returns `%{}` outside
  tests — the app is env-var-only; no `MASTER_KEY` / `EncryptedSecrets` /
  `SECRETS_DIRECTORY` read.
- `server/Dockerfile`: dropped the `COPY .../*.yml.enc`, the `rm -rf` block, and
  `ENV SECRETS_DIRECTORY=...`.
- Removed `lib/mix/tasks/secrets/edit.ex` (nothing left to edit).
- Updated the dev docs (`README.md`, `AGENTS.md`, the contributors doc, the
  Slack `AGENTS.md`) to the fnox flow.

> ⚠️ Because the app is now env-var-only with no blob fallback, the first deploy
> relies entirely on the 1P-sourced env vars. The all-or-nothing ESO sync fails
> the deploy at the migration hook if any item is missing (not silently), and
> the audit confirmed every consumed secret has an env source — but there is no
> safety net, so verify per the Step 4 checks during the cascade.

**Follow-up (separate PR — not required to delete the blob):**

- Retire the now-unused `MASTER_KEY` wiring: the env refs in the server /
  migration / processor / xcresult-processor templates, the `masterKey` /
  `$syncMaster` path in `external-secrets.yaml`, and `server.masterKey` /
  `server.externalSecrets.masterKey` in values. It's coupled to
  `server.managedSecrets`, so decouple carefully. Until then the `MASTER_KEY`
  1P item must stay (ESO still syncs it; the app just ignores it).
- Drop the dead accessors (`mautic_*`, `anthropic_api_key`, `openai_api_key`,
  `ipv4_database_url`) and the unused `encrypted_secrets` dep — harmless no-ops
  now (they resolve to `nil`).
