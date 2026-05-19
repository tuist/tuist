---
name: tuist-elixir-review
description: Project-specific PR-review rules for the tuist/tuist Elixir codebases (server, cache, processor, xcode_processor, tuist_common, noora). Focuses on the things only this repo knows — authorization invariants, tenancy, write-only ClickHouse, Mimic placement, migration timestamptz, data-export updates, marketing changelog entries, and i18n.
---

# Tuist Elixir Review

This skill is intentionally narrow. **Generic Elixir style, naming, pipe
chains, formatting, nesting depth, and `String.to_atom/1`-style hygiene
are already covered by `mix format` and `credo` in CI — do not flag
those.** Focus on the rules below; they catch real bugs.

For each finding, cite `path:line` (or `Module.function/arity`) and
quote the relevant snippet.

Only report findings whose cited snippet is present in the PR diff. If
the concern comes from unchanged context, do not emit a finding, do not
mention it as a note, and do not create a "findings outside this PR's
diff" section. If every possible concern is outside the diff, return no
findings.

Do not infer violations from nearby lines. A Mimic finding requires the
exact token `Mimic.copy(` on the cited changed line. A migration
timestamp finding requires the cited changed line to contain
`timestamps()` without `type: :timestamptz` or a timestamp column without
`:timestamptz`.

---

## 1. Authorization — `lib/tuist/authorization.ex` + `AuthorizationPlug`

The policy DSL is `LetMe.Policy`. Categories are declared via `object
:foo do ... end` blocks. The API plug at
`server/lib/tuist_web/plugs/api/authorization/authorization_plug.ex`
hard-codes which categories are project-scoped:

```elixir
@project_categories [:run, :bundle, :cache, :preview, :test, :build, :automation_alert]
```

### Flag

- **A new `object :foo do` block (project-scoped resource) without `:foo` being added to `@project_categories`** in `authorization_plug.ex`. The route guard will silently miss the new category. **Severity: high.**
- **An `action` that uses `[:authenticated_as_project, ...]` but omits `:projects_match`.** This lets an authenticated project act on *another* project's resource. **Severity: critical.** The canonical correct form is `allow([:authenticated_as_project, :projects_match])`.
- **`:public_project` or `[:authenticated_as_user, :ops_access]` allowed for `:create`, `:update`, or `:delete` actions.** These flags are intended for read-only paths.
- **A new `action :read | :create | :update | :delete` that doesn't cover all three subject kinds** (`:authenticated_as_user`, `:authenticated_as_project`, `:authenticated_as_account` with a `scopes_permit:` check) **without an inline `desc(...)` explaining the omission.** Missing one is usually a bug; an explicit `desc` is the documented escape hatch.
- **An account-token `allow` without a `scopes_permit:` check** (e.g. bare `[:authenticated_as_account]`). Account tokens must always be scope-gated.

### Do not flag

- Existing `object`/`action` blocks unchanged by the diff.
- Reordering of `allow(...)` lines within an action.
- `/ops` LiveView routes. They are not API `AuthorizationPlug`
  categories and do not belong in `@project_categories`.

---

## 2. Tenancy — bare `Repo.get` on multi-tenant schemas

Tenant-owned schemas include at least: `Bundle`, `Run`, `Cache`,
`Preview`, `CommandEvent`, `Build`, `Test`, `Project`,
`AutomationAlert`. They all carry a `project_id` or `account_id`.

### Flag

- **`Tuist.Repo.get(Schema, id)` / `Repo.one(from(s in Schema, where: s.id == ^id))` without a `project_id` / `account_id` constraint** for any of the schemas above, when the call is inside a controller, plug, LiveView, channel, MCP handler, or worker that already has the project/account in scope. This is a tenant leak (an attacker who guesses a UUID gets cross-tenant data). **Severity: high.**
- **A new context function that takes an `id` and forwards it to `Repo.get` without also taking the project/account.**

### Do not flag

- Internal background jobs that intentionally operate across tenants **with an explicit `# admin / cross-tenant: ...` comment** or a function name like `*_for_all/_global/_admin`. These are documented cross-tenant paths by design.
- Reads from non-tenant tables (`User`, `Account`, `Organization`, `Subscription`, etc.).
- **Webhook handlers operating on a row that was already cryptographically selected upstream.** When `lib/tuist_web/plugs/webhook_plug.ex` resolves a per-row HMAC secret (e.g. `GitHubController.resolve_webhook_secret/1` matches a `GitHubAppInstallation` row whose `webhook_secret` HMACs the raw body, then stashes the row on `conn.assigns[:github_installation]`), downstream handlers reading that assign do not need a separate `installation.account_id == expected_account_id` check. There is no separate "expected account" — webhooks land on a global `/webhooks/<provider>` URL, and the row *is* the tenant context, selected by a per-row cryptographic capability. A redundant `account_id` equality check after `valid_signature?/4` would compare the row's value to itself; it adds dead code, not a defense layer. If the cryptographic check fails, the request 403's before the handler ever runs.
- **Internal dispatch paths whose inputs come from a query already scoped by tenant.** When a function receives a struct produced by an upstream context function that already filters by `project_id` / `account_id` (e.g. `FlakyTestsMonitor.evaluate/1` → `AlertEvaluationWorker` → `ActionExecutor`), do not flag the downstream call as needing its own scoping check. Trace the input chain before flagging; only flag when the input is user-controllable (URL param, body field, header).
- Functions documented in their `@doc` as cross-tenant (e.g. "Loads a single endpoint by id, regardless of account"). The docstring is the explicit boundary marker.

---

## 3. ClickHouse `IngestRepo` is write-only

There are **two** ClickHouse repos in this codebase, and they are not
interchangeable. Be precise about which one a call uses before flagging.

- **`Tuist.IngestRepo`** — write-only ingest path. Application code must
  not read from it; reads happen out of band.
- **`Tuist.ClickHouseRepo`** — the read-only ClickHouse repo (declared
  with `read_only: true` in `server/lib/tuist/clickhouse_repo.ex`).

### Flag (Severity: high)

- Any call to `Tuist.IngestRepo.all/1`, `Tuist.IngestRepo.get/2`,
  `Tuist.IngestRepo.get_by/2`, `Tuist.IngestRepo.one/1`,
  `Tuist.IngestRepo.exists?/1`, or `Tuist.IngestRepo.aggregate/3`.
- Any `from(... ) |> Tuist.IngestRepo.<read fn>`.

The fix is almost always to read through `Tuist.ClickHouseRepo` (for
ClickHouse-only data) or `Tuist.Repo` (PostgreSQL).

### Do not flag

- `Tuist.ClickHouseRepo.all/1`, `Tuist.ClickHouseRepo.one/1`,
  `Tuist.ClickHouseRepo.aggregate/3`, or any other read through
  `ClickHouseRepo`. That repo exists specifically for application reads.
  Do **not** confuse it with `IngestRepo`.
- Writes via `Tuist.IngestRepo.insert/2` / `insert_all/2,3` — those are
  the intended use.

---

## 4. Test setup — Mimic copies belong in `test_helper.exs`

`server/test/test_helper.exs` is the single place where
`Mimic.copy(Module)` is called. Per-test-file `Mimic.copy/1` calls leak
state across tests and are an explicit anti-pattern in this repo.

### Flag

- A `Mimic.copy(...)` call inside any file under `server/test/` other
  than `test_helper.exs`. Suggest: move it to `test_helper.exs`.

### Do not flag

- `Mimic.expect/3`, `Mimic.stub/3`, `Mimic.reject/1` — those belong in tests.
- `Mimic.copy/1` calls in `test_helper.exs` itself.
- `import Mimic`, `use Mimic`, `setup :set_mimic_from_context`, aliases,
  or any other test setup line that does not contain `Mimic.copy(`.
- A test file that merely uses Mimic (`use Mimic`, `import Mimic`,
  `stub`, `expect`, `reject`) but does not contain the exact
  `Mimic.copy(` call in the diff.

---

## 5. Migrations — timestamps must be timezone-aware

In `server/priv/repo/migrations/` and `server/priv/ingest_repo/migrations/`:

### Flag (Severity: medium)

- A new column declared as `timestamps()` without
  `type: :utc_datetime_usec` *and* a corresponding migration column
  without `:timestamptz`. The `.credo.exs` rule says: migrations use
  `:timestamptz`, schemas (`lib/`) use `:utc_datetime`.
- `add :inserted_at, :naive_datetime` or `:datetime` without timezone in a migration. Should be `:timestamptz`.

### Do not flag

- `timestamps(type: :timestamptz)`.
- `def change do`, `create table(...)`, blank lines, comments, or any
  line that does not itself declare a timestamp type.
- `add :started_at, :timestamptz`, `add :finished_at, :timestamptz`,
  or any other explicit `:timestamptz` column.

---

## 6. `data-export.md` updates on schema changes

`server/data-export.md` documents every piece of customer data Tuist
stores, for GDPR Article 20 / CCPA exports. **It must be updated when
the diff includes** any of:

- A new migration adding a table
- A new migration adding a column that stores customer / user / project
  data (not internal bookkeeping)
- A new Ecto schema in `server/lib/tuist/**/*.ex` that maps to a
  customer-facing table
- New file storage paths in S3 (e.g. new keys under `bundles/`,
  `previews/`, `caches/`)

### Flag (Severity: medium)

- A diff that touches `server/priv/repo/migrations/*.exs` (other than
  pure index / constraint changes) or `server/priv/ingest_repo/migrations/*.exs`
  **without** also modifying `server/data-export.md`.

This is a compliance gap, not just a docs nit — call it out clearly.

---

## 7. i18n — currency symbols are not translatable

In marketing copy and pricing UI:

### Flag

- Currency amounts (`€`, `$`, `£`, `¥`, currency codes) wrapped inside
  `dgettext/2` or `gettext/1`. Symbols and amounts must remain identical
  across languages.
- Example anti-pattern: `dgettext("marketing", "0€ and up")`. The
  correct form keeps the currency literal outside the translation:
  `"0€ " <> dgettext("marketing", "and up")`.

### Do not flag

- Descriptive text *around* prices (e.g., the words "and up", "per
  unit", "billed annually") — those should be translated.

---

## 8. Translation files — `.po` is read-only for humans

### Flag (Severity: high)

- Any modification to `server/priv/gettext/**/*.po`. Only the `tuistit`
  bot may edit `.po` files; CI will fail otherwise.
- Use of `mix gettext.extract --merge`. Only the no-`--merge` form is
  allowed in PRs.

### Do not flag

- `.pot` (template) changes — those are produced by `mix gettext.extract`
  and are expected when adding new translatable strings.

---

## 9. N+1 queries — DB calls inside loops

A `Repo.*` / `ClickHouseRepo.*` / `IngestRepo.*` call inside `Enum.map`,
`Enum.each`, `Enum.flat_map`, `Enum.reduce`, `for`, or
`Stream.*` is almost always an N+1. Each iteration is a separate round
trip; the chart-bucket loop or per-row preload that looked harmless on
toy data stalls real page loads.

**Actively search the diff for these patterns** before signing off
— don't just react to obvious cases:

- `Enum.map(_, fn ... -> ... <Repo>.<one|all|get|get_by|aggregate|exists?|stream> ... end)`
- `Enum.map(_, &<Repo>.<...>(&1, ...))` (point-free form is the same trap)
- `Enum.each(_, fn ... -> ... <Repo>.<insert|update|delete> ... end)`
- `Enum.flat_map`, `Enum.reduce(..., fn _, acc -> ... <Repo>... end)`
- `for x <- xs, do: <Repo>.*` / `for x <- xs, do: ...` with a query inside
- `Enum.map(_, &<Repo>.preload(&1, ...))` — `preload/2` already accepts a list
- Pipelines like `xs |> Enum.map(&fetch_thing/1)` where `fetch_thing/1`
  internally calls a `Repo` — follow the function one hop in.

The repos to watch: `Tuist.Repo`, `Tuist.ClickHouseRepo`,
`Tuist.IngestRepo`, plus any aliased form (e.g. `alias Tuist.Repo`,
then bare `Repo.*` inside the loop).

### Flag (Severity: medium; high if hot path)

- A `Repo`/`ClickHouseRepo`/`IngestRepo` read or aggregate inside any
  `Enum.*`/`for`/`Stream.*` in the diff. Severity is **high** if the
  loop is on a request path (controller, LiveView mount/handle_*,
  channel, MCP handler) or scales with tenant data (test cases,
  bundles, runs); **medium** for background jobs and one-shot scripts.
- Per-element `Repo.preload/2` — `preload` already takes a list; one
  call covers all.
- Per-element inserts/updates/deletes that have an `_all` equivalent
  (`insert_all`, `update_all`, `delete_all`).

When suggesting a fix, **name the consolidating primitive** so the
author can act on it directly:

- ClickHouse per-bucket aggregation → `argMaxIf` / `countIf` /
  `groupArray` over a single GROUP BY, or `arrayJoin` to fan out
  buckets as rows.
- Ecto per-row lookup → `where: r.id in ^ids` + group in Elixir, or
  a join.
- Per-element preload → `Repo.preload(list, [:assoc])` once.
- Per-element write → `*_all` + a list of params.

### Do not flag

- Loops over a bounded constant collection (config keys, enum members,
  ≤5 items) where each query is genuinely independent and the loop
  isn't on a hot request path.
- Tests, fixtures, and seed scripts (`server/test/`,
  `server/priv/repo/seeds*.exs`) — correctness-first, perf is fine.
- Loops that build params in memory with no DB round trip per iteration.
- `Repo.stream/2` inside `Enum.*` with an explicit comment justifying
  the cursor-based stream (e.g. "stream so we don't load 10M rows").
- Pre-existing N+1s untouched by the diff — this skill is for new
  regressions, not codebase-wide audits.

---

## 10. Inline `style="..."` in HEEx templates

Component styling lives in `server/assets/app/css/pages/*.css` (or
`noora/lib/noora/**/*.css` for design-system primitives), keyed off
`data-part` selectors that mirror the HEEx structure. Inline `style=`
attributes on elements or component props bypass the design tokens
(`var(--noora-spacing-*)`, `var(--noora-font-*)`, etc.) at review
time, leak presentation into LiveView diffs, and prevent themers /
density modes from overriding the value.

### Flag (Severity: low)

- A new `style="..."` attribute on an HTML element inside any
  `server/lib/tuist_web/**/*.html.heex` or `*_live.html.heex`.
- A `style=` prop passed to a Noora component (`<.button_group
  style="...">`, `<.text_input style="...">`, etc.). These flow through
  to the underlying element via `{@rest}`, so they're inline styles by
  another name.

When suggesting a fix:

1. Add a stable `data-part` (or reuse one already on the element).
2. Move the rule into the matching page CSS file
   (`server/assets/app/css/pages/<page>.css`) or, if it belongs to a
   reusable component, the Noora primitive's CSS.
3. Prefer Noora design tokens (`--noora-spacing-*`, `--noora-radius-*`,
   `--noora-font-*`, `--noora-surface-*`) over raw values.

### Do not flag

- `style=` attributes that already existed before the diff.
- Generated SVG markup with inline styles (it's the artist tool's
  output, not author-written).
- One-off `style="display: none"` toggles whose visibility is driven
  by a temporary Phoenix `:if` — those still belong in CSS, but the
  signal-to-noise here is low.

---

## 11. Marketing changelog for user-facing server/dashboard features

The human-authored product changelog lives in
`server/priv/marketing/changelog/*.md`. Generated files such as
`server/CHANGELOG.md` or root `CHANGELOG.md` must not be edited by
authors.

### Flag (Severity: medium)

- A PR that adds or materially changes a user-facing server/dashboard
  feature without also adding or updating a
  `server/priv/marketing/changelog/*.md` entry.

### Do not flag (important exclusions to avoid noise)

- **Fix PRs** — bug fixes, corrections to existing flows, validation
  improvements, error message tweaks, or UI adjustments that make an
  already-announced or already-shipped feature work correctly. These
  repair rather than launch.
- **Ops-only, admin-only, or internal infrastructure changes** — even if
  visible in dashboard code, if the behavior is gated to operators (`/ops`
  routes), requires `ops_access`, or is infrastructure-only, it is not
  a customer-facing product announcement.
- **Features behind account/org feature flags for internal rollout** —
  if the PR adds code that is not yet broadly available to customers
  (gated by `FunWithFlags`, `Environment.dev?/ops?`, or similar), and
  the PR does not also make the feature generally available, the
  changelog entry should wait until general availability.
- **Refactors, performance work, telemetry, and test-only changes**
  without customer-visible behavioral changes.
- **Documentation-only or marketing-only PRs.**
- **CLI/app/cache/kura/noora-only changes** — this rule is for
  server/dashboard features.
- **PRs that already add or update a matching
  `server/priv/marketing/changelog/*.md` entry.**

When suggesting a fix, ask for a short marketing changelog entry with
frontmatter like `title`, `category: "Product"`, and `pull_request`.
Mention an accompanying image under
`server/priv/static/marketing/images/changelog/` only when the feature
has a visual dashboard/UI state worth showing.

---

## 12. Changeset functions must have tests

Ecto changeset functions in schema modules under `server/lib/tuist/`
(`def changeset/N`, `def create_changeset/N`, `def update_changeset/N`,
or any other `*_changeset/N`) encode validation and persistence
contracts. New or materially changed changeset bodies that ship without
tests regress silently: a deleted `validate_*`, a widened `cast` list,
or a missing `unique_constraint` won't fail CI — the first signal is a
production error or a malformed row.

The convention in this repo is one `<schema>_test.exs` per schema module
that asserts on `errors_on(changeset)` for invalid inputs and
`changeset.valid?` for valid ones — see
`server/test/tuist/projects/project_test.exs` and
`server/test/tuist/cache_action_items/cache_action_item_test.exs` for
canonical examples.

### Flag (Severity: medium)

- A new `def changeset(`, `def create_changeset(`, `def update_changeset(`,
  or any `def *_changeset(` added in a `server/lib/tuist/**/*.ex` file
  whose diff does **not** also add at least one test case calling that
  function (e.g. `WebhookEndpoint.create_changeset(...)`,
  `Project.update_changeset(...)`) in `server/test/tuist/**/*_test.exs`.
- A materially changed changeset body — a new or modified `cast`,
  `validate_required`, `validate_length`, `validate_format`,
  `validate_inclusion`, `validate_change`, `unique_constraint`,
  `foreign_key_constraint`, or `put_change` line in the diff — where
  the change isn't exercised by a test added or modified in the same
  diff.

When flagging, name the schema module and point to a sibling
`<schema>_test.exs` as the place to add coverage. If no such test file
exists, request its creation alongside the changeset.

### Do not flag

- Trivial mechanical edits (renaming a field already covered by an
  existing test, removing a single `cast` field, formatting-only churn,
  reordering pipe steps inside an unchanged body).
- Changeset functions in `server/test/support/` fixtures or
  `server/priv/repo/seeds*.exs`.
- Diffs that exercise the changeset indirectly through a higher-level
  context test (e.g. `accounts_test.exs` calling
  `Accounts.create_user/1`, which in turn invokes the changeset) — that
  counts as coverage. Only flag when the diff has *no* test reference
  to the schema module or its changeset functions.
- Changeset edits that are purely a consequence of a column rename
  already covered by a migration-level test or by an existing
  `errors_on(changeset)` assertion that still passes against the new
  field name.

---

## Out of scope (handled elsewhere — do not flag)

- Module / function naming, pipe-chain start, function ordering,
  parentheses-on-no-arg-calls → `mix format` + `credo` (`PipeChainStart`,
  `StrictModuleLayout`, `Nesting`, `UnsafeToAtom`, `ModuleDoc`).
- Missing `@spec` / `@type` — this codebase intentionally avoids
  typespecs. Never suggest adding them.
- Missing `@doc` / `@moduledoc` on internal helper modules.
- `String.to_atom/1` on user input — credo's `UnsafeToAtom` covers it.

## Before submitting findings

For each finding, confirm:

1. The `path:line` is real and the snippet appears in the diff.
2. The category above is one of 1–12; if it isn't, downgrade to a
   question (`uncertain: ...`) rather than asserting a finding.
3. The severity is set: **critical** (auth bypass / cross-tenant read or
   write), **high** (likely security or correctness bug), **medium**
   (compliance / consistency gap), **low** (nice-to-have).
4. You are not reporting an unchanged line as a finding. Unchanged
   context can explain a diff finding, but cannot be the finding itself.
