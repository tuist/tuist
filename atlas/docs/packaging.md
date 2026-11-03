# Packaging Atlas as a standalone product

Atlas grew as Tuist's internal operations app. This document records where it is
still coupled to Tuist (the company, its product, its infrastructure and the
monorepo) and the work needed to open-source it and let other companies run it.
It is an audit and a plan, not a commitment to a timeline.

## Where Atlas stands today

- **Booting outside Tuist works.** The published image starts with Postgres and
  four secrets (`DATABASE_URL`, `SECRET_KEY_BASE`, `GUARDIAN_SECRET_KEY`,
  `ENCRYPTION_KEY`), plus `PHX_HOST`, `ATLAS_ALLOWED_EMAIL_DOMAIN` and Google
  OAuth credentials to be usable. Nearly every integration (Slack, Mailgun,
  Stripe, banks, GitHub, LLMs, ClickHouse, object storage, push, Sentry) is
  env-gated and off by default. `compose.yaml` and the Helm chart's default
  values already describe a standalone deployment.
- **Building outside the monorepo does not work.** Atlas depends on `../noora`,
  takes its Erlang and Elixir versions from the root `mise.toml`, and its
  Dockerfile builds from the repository root and copies `infra/certificate-trust/`.
- **Most domain code is already product-neutral:** Orbit, automations, briefs,
  tasks, notes, documents, search, signals, presence, audit, OAuth, connections,
  inference, moodboard, insurance, assets, the MCP proxy framework, the
  environments behaviour and the account handle registry.
- **The coupling that remains** falls into five groups, in rough order of
  importance below.

## 1. Build and monorepo coupling (blocks a standalone repository)

| Item | Where | Action |
| --- | --- | --- |
| Noora path dependency | `mix.exs` (`{:noora, path: "../noora"}`) | Depend on the Hex release (MIT). Check Atlas does not rely on unreleased Noora changes. |
| Noora asset build | `mix.exs` `assets.setup`/`assets.build` (`cmd --cd ../noora aube ...`), `config/config.exs` esbuild aliases to `../../noora/priv/static` | Use the prebuilt `priv/static/noora.{js,css}` from `deps/noora` and drop the `aube` steps. |
| Toolchain pins | root `mise.toml` | Pin Erlang, Elixir and Node in `atlas/mise.toml`. Move Tuist ops tools (kubectl, helm, 1Password CLI, clusterctl) to a private overlay. |
| Dockerfile | `Dockerfile` | Build from `atlas/` only, remove the Noora stage, and vendor or drop the `infra/certificate-trust` check. |
| CI and releases | `.github/workflows/atlas*.yml`, root `once.toml`, `mise/tasks/release/*` | Standalone workflows using plain `mix` (or a local `once.toml`) on public runners. |
| Helm chart | `infra/helm/atlas/` (outside `atlas/`), `deploy/validate.sh` | Move the chart, without the managed overlay, under `atlas/deploy/`. |
| Git dependencies | `mix.exs`: `tuist/condukt`, `tuist/ecto_ch` fork, `emcp` fork, `boruta` on `master` | Keep public, pin `boruta` to a commit, plan Hex releases. |
| Changelog config | `cliff.toml` | Point links at the new repository. |

`tuist_common` is not used, so it needs no change.

## 2. Risky Tuist defaults (fix before anyone else boots Atlas)

These are configurable but fall back to Tuist values, which can silently
misbehave on another company's install.

- **Sign-in domain** defaults to `tuist.dev` and only warns in production
  (`config/runtime.exs`). Make `ATLAS_ALLOWED_EMAIL_DOMAIN` required in prod.
- **Slack agent identity** defaults to `pedro@tuist.dev`
  (`config/runtime.exs`, `lib/atlas/slack/conversation_agent.ex`). Remove the default.
- **Slack channel IDs** of the Tuist workspace are defaults in config
  (`C0C5LBMM278`, `C0AGV3YU8ET`, `C072A0Z53B7`, `C061VCZC2V8`) and module
  attributes that ignore config (`gtm/audience_member_notifier.ex`,
  `gtm/blog_post_idea_notifier.ex`, `accounts/invoice_paid_notifier.ex`). Read
  all of them from config with `nil` defaults and move Tuist's values to the
  managed Helm values.
- **Support chat embed** allows `https://tuist.dev` as a parent origin by default
  (`config/runtime.exs`, `lib/atlas_web/support_chat_embed.ex`). Default to none.
- **Other defaults** to empty or required-when-enabled: inbox sender domains,
  finance internal entities (`Tuist GmbH,Tuist Inc.`), Mailgun domain, object
  storage endpoint (Hetzner), GitHub App name/owner/repo, GTM and support
  senders, `TUIST_SERVER_INTERNAL_URL`, `ATLAS_TUIST_ENVIRONMENT_URL`.
- **ClickHouse password** falls back to `SECRET_KEY_BASE`. Make it explicit.

## 3. Branding and identity (make configurable)

Introduce one company/brand configuration (name, legal entity, site and terms
URLs, support address, sender addresses, logo/wordmark/favicon/email image,
accent colour, internal mail domain) and use it everywhere below.

- **Hardcoded hosts:** `atlas.tuist.dev` as the internal mail domain and in
  Message-IDs, internal-address filtering and prompts (`support.ex`,
  `accounts/event_routing.ex`, `inbox.ex`, `accounts/agents/email_event_agent.ex`)
  and demo docs links. Derive from `PHX_HOST` or a new inbox domain setting.
- **Email templates:** `no-reply@tuist.dev`, `tuist.dev` links, `/terms`,
  "© Tuist GmbH" and `tuist_email.png` (`gtm/email.ex`, `accounts/pocs/*`).
- **UI assets:** `tuist-logo*.svg`, wordmarks and Tuist favicons used by five
  templates. Add a `<.brand_logo/>` component reading the brand config; ship
  neutral defaults (`logo.svg` already exists).
- **UI copy:** about 40 strings name Tuist (support page, public POC page,
  sidebar label, hardware/licenses/insurance/GTM descriptions, tax certificate
  copy, `"Tuist"` as the outbound author label). Some are not in gettext yet.
  Interpolate the configured name, then re-extract `.pot` templates.
- **Theme:** the default accent is Tuist purple (`--noora-purple-500`). Add an
  overridable `--atlas-accent` palette.
- **LLM prompts and tool descriptions** describe "Tuist" and `contact@tuist.dev`
  (support classifier, Granola meeting agent with its `tuist_usage_signal`
  parameter, email event agent, payment detection, outreach recommendation, MCP
  server instructions, several tool descriptions). Template them from the
  company profile.
- **Native app identity:** `dev.tuist.atlas` bundle ID, URL scheme, APNs topic and
  Android package are hardcoded. Either make them configurable together or state
  that the official native apps are Tuist-distributed.
- **Edge header:** `x-tuist-public` matches Tuist's Cloudflare rules. Rename it
  (for example `x-atlas-public`) together with `infra/flux/cloudflare-config`.
- **Commercial vocabulary:** plan tiers (`enterprise pro free`), the
  "Tuist Enterprise" Stripe line item and EUR assumptions in invoices, revenue
  and snapshots. Make tiers configurable and reuse the finance report currency.
- **Cosmetic:** `tuist-*` CSS part names, "Ported from TuistWeb" comments,
  `service.namespace: "tuist"` in OTel config, sample placeholders such as
  `github.com/tuist/tuist/pull/123` and the hardcoded "Hive"/"Tuist" project sort.

## 4. Tuist product integrations (move behind adapters)

These call Tuist's APIs or model Tuist's product. They are config-gated but
compiled into core. Group them into an optional Tuist integration that registers
itself through small extension points.

- **Tuist server client** (`Atlas.TuistServer`, Kubernetes workload identity with
  audience `tuist-server`), used by about 25 files. Define a product analytics
  source behaviour.
- **MCP:** six `*_tuist_postgres`/`*_tuist_clickhouse` tools and four feature-flag
  tools are listed statically in `Atlas.MCP.Server` and allowlisted by name in
  `orbit/tool_policy.ex`. Add a tool registry so integrations register tools,
  scopes and Orbit policies. The `MCP_PROXY_SERVERS=tuist-managed` preset and the
  `x-tuist-atlas-identity` header belong in managed values, with the identity
  token behind a provider behaviour.
- **Overview page** (`Atlas.TuistOverview`, `OverviewLive` at `/`) shows Tuist
  product metrics. Make it an optional widget and give `/` a generic home.
- **Feature usage** catalog and collector query Tuist tables. Keep the snapshot
  storage in core behind a feature usage source behaviour; the catalog comes from
  the integration. The Loki query hardcodes `service_name="tuist-server"`.
- **Nudges:** Air, cache, selective testing, SSO and activation signals are
  Tuist-specific. Keep the framework and add a signal registry instead of the
  static list in `nudges/workers/evaluate_signals.ex`.
- **Feature flags** (`Atlas.TuistFeatureFlags`) and the `Environments.Tuist`
  provider (already behind a behaviour) move into the integration.
- **Account handles:** generic mechanism, but UI copy says "Tuist handles" and the
  Sentry tag names (`auth_account_handle`, `selected_account_handle`) are Tuist
  server conventions. Make them configurable.

The agent feedback ingest (`POST /api/support/agent-feedback`) is already
product-neutral: products map their own identities onto `reporter_*`,
`account_handle`, `project_handle`, `organization_handles` and `source`.

## 5. Tuist-only features and data

- **Licenses:** issues keys in Tuist Server's air-gapped license format. Optional
  module, off by default.
- **Contracts:** hosted and self-hosted order forms, enterprise contract prompt.
  Ship generic template stubs and a configurable template set.
- **Letters and time off:** the Berlin tax certificate request (German form PDF,
  `DE`-only letters) and the Berlin default holiday calendar (seeded by a
  migration and set as a column default). Make jurisdictions a pluggable pack and
  the default location configurable.
- **GTM outreach:** curated iOS/Swift topics, Tuist keyword scoring, the
  `tuist_mention` signal kind and "Public Tuist advocate" titles. Make topics and
  keywords data-driven and rename the kind to `brand_mention` (data migration).
- **POC taxonomy:** mobile-heavy CI and language enums. Make them configurable.
- **Seeds and migrations:** `priv/repo/seeds.exs` (about 6,400 lines) contains
  real employee names, Tuist emails, Slack channels and companies; rewrite it
  around a fictional company. Migrations insert Tuist alert rules with a real
  Slack channel ID, rename Tuist audiences and seed Berlin. Squash or neutralise
  them for the open-source baseline.
- **Generated contracts:** `priv/automation/contracts/v1.json` lists the Tuist
  tools and descriptions; regenerate after the integration split, as a new
  contract version.

## 6. Private operations assets (keep out of the public repository)

- `infra/helm/atlas/values-managed-production.yaml` and `values-demo.yaml`
  (hosts, Apple team ID, Slack IDs, about 50 1Password references).
- Deployment workflows (`atlas-release.yml` deploy jobs, inbox worker deploy,
  native app signing workflows).
- `atlas/fnox.toml` (age-encrypted Tuist secrets; consider rotation if history is
  published), `workers/inbox/wrangler.toml` values, Tuist runbooks in
  `deploy/AGENTS.md`, internal proposals in `atlas/docs/`, and the Tuist-specific
  parts of `AGENTS.md` and `data-export.md`.
- Chart defaults that are Tuist-shaped: `externalSecrets.storeRef.name:
  onepassword` and the `tuistServer` block. Rename to a generic upstream identity
  block or move to the overlay.

## 7. Licensing

- Atlas is MPL-2.0 with Exhibit B. That is OSI-approved and allows open-sourcing.
  It is file-level copyleft and does not cover network use, so others could host
  Atlas commercially; choosing between MPL, AGPL or a source-available license is
  a business decision to make before publishing.
- Add a copyright holder and, optionally, SPDX headers.
- Run a dependency license scan over `mix.lock` and the bundled fonts (Geist Mono
  is OFL; include its notice).
- The managed deployment borrows a public Codex OAuth client ID; review the terms
  before offering ChatGPT connections on self-hosted installs.

## Suggested order

1. Build decoupling (section 1), so Atlas builds from its own directory.
2. Risky defaults (section 2), so a fresh install cannot inherit Tuist identity.
3. Brand configuration and copy (section 3).
4. Integration extension points and the Tuist integration split (section 4),
   then optional modules for section 5.
5. Seed and migration hygiene, private ops split, and the licensing decision
   (sections 5 to 7), right before publishing.

Rough size: about one engineer-week for sections 1 and 2, one to two weeks for
branding, two to three weeks for the integration split and optional modules, and
up to a week for data hygiene and the repository split.
