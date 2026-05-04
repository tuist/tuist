---
name: tuist-elixir-review
description: Project-specific PR-review rules for the tuist/tuist Elixir codebases (server, cache, processor, xcode_processor, tuist_common, noora). Focuses on the things only this repo knows — authorization invariants, tenancy, write-only ClickHouse, Mimic placement, migration timestamptz, data-export updates, and i18n.
---

# Tuist Elixir Review

This skill is intentionally narrow. **Generic Elixir style, naming, pipe
chains, formatting, nesting depth, and `String.to_atom/1`-style hygiene
are already covered by `mix format` and `credo` in CI — do not flag
those.** Focus on the rules below; they catch real bugs.

For each finding, cite `path:line` (or `Module.function/arity`) and
quote the relevant snippet.

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

---

## 2. Tenancy — bare `Repo.get` on multi-tenant schemas

Tenant-owned schemas include at least: `Bundle`, `Run`, `Cache`,
`Preview`, `CommandEvent`, `Build`, `Test`, `Project`,
`AutomationAlert`. They all carry a `project_id` or `account_id`.

### Flag

- **`Tuist.Repo.get(Schema, id)` / `Repo.one(from(s in Schema, where: s.id == ^id))` without a `project_id` / `account_id` constraint** for any of the schemas above, when the call is inside a controller, plug, LiveView, channel, MCP handler, or worker that already has the project/account in scope. This is a tenant leak (an attacker who guesses a UUID gets cross-tenant data). **Severity: high.**
- **A new context function that takes an `id` and forwards it to `Repo.get` without also taking the project/account.**

### Do not flag

- Internal background jobs that intentionally operate across tenants (look for an explicit `# admin / cross-tenant: ...` comment or a function name like `*_for_all/_global/_admin`).
- Reads from non-tenant tables (`User`, `Account`, `Organization`, `Subscription`, etc.).

---

## 3. ClickHouse `IngestRepo` is write-only — `ClickHouseRepo` is read-only

There are **two** ClickHouse repos in this codebase. They are NOT
interchangeable — confusing them produces false positives.

| Repo | Purpose | Flag reads? |
|------|---------|-------------|
| **`Tuist.IngestRepo`** | Write-only ingest path | **YES** — never read |
| **`Tuist.ClickHouseRepo`** | Read-only queries (`read_only: true`) | **NO** — this IS the allowed read path |

### Flag (Severity: high)

- Any call to `Tuist.IngestRepo.all/1`, `Tuist.IngestRepo.get/2`,
  `Tuist.IngestRepo.get_by/2`, `Tuist.IngestRepo.one/1`,
  `Tuist.IngestRepo.exists?/1`, or `Tuist.IngestRepo.aggregate/3`.
- Any `from(... ) |> Tuist.IngestRepo.<read fn>`.

### Do not flag — critical distinction

- **NEVER flag reads through `Tuist.ClickHouseRepo`**. This repo exists
  specifically for application reads from ClickHouse. The
  `server/lib/tuist/clickhouse_repo.ex` module declares `read_only: true`.
- `Tuist.ClickHouseRepo.all/1`, `Tuist.ClickHouseRepo.one/1`,
  `Tuist.ClickHouseRepo.aggregate/3` — these are the CORRECT way to read
  ClickHouse data in application code.
- Writes via `Tuist.IngestRepo.insert/2` / `insert_all/2,3` — those are
  the intended use of the write path.

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

---

## 5. Migrations — timestamps must be timezone-aware

In `server/priv/repo/migrations/` and `server/priv/ingest_repo/migrations/`:

### Flag (Severity: medium)

- A new column declared as `timestamps()` without
  `type: :utc_datetime_usec` *and* a corresponding migration column
  without `:timestamptz`. The `.credo.exs` rule says: migrations use
  `:timestamptz`, schemas (`lib/`) use `:utc_datetime`.
- `add :inserted_at, :naive_datetime` or `:datetime` without timezone in a migration. Should be `:timestamptz`.

---

## 6. Migration backfill ordering and race conditions

Backfills that populate new tables/MVs from existing data must account for
concurrent writes happening during the migration window.

### Flag (Severity: high)

- **Backfilling before establishing the live sync mechanism** (e.g.,
  backfilling from PostgreSQL before creating a ClickHouse Materialized View
  trigger). Rows inserted between the backfill scan and the MV creation will
  be permanently lost. The MV only captures changes from its creation time
  forward.
- **Async buffered writes without durability on crash** (e.g.,
  `Tuist.Ingestion.Buffer` with async mode). If the buffer process crashes
  and restarts between PG commit and CH flush, the in-flight rows are lost
  with no replay mechanism. Flag when a migration relies on async ingestion
  without confirming the buffer is sync-only for that path or has explicit
  crash-recovery replay logic.
- **Dual-write backfills without a "processed" flag** to distinguish
  pre-migration from post-migration rows. If live traffic continues inserting
  during the backfill, the backfill may race with the dual-write and create
  duplicates or miss rows.

### Safe patterns

- Create the MV/trigger first (captures new changes), then backfill historical
  data, ensuring the backfill query excludes rows already captured by the MV.
- Use a "watermark" column (`backfilled_at`, `replicated_to_ch`) to resume
  from interruption and avoid re-processing.

---

## 7. `data-export.md` updates on schema changes

`server/data-export.md` documents customer data for GDPR Article 20 / CCPA
exports. Internal bookkeeping (replication flags, sync timestamps,
`replicated_to_ch`, `processed_at`, etc.) belongs in the Non-Exportable
Data section, not the exportable list.

### Flag (Severity: medium)

- A diff that adds a **new customer-facing table** (stores user/project
  data) or **new S3 storage paths** (`bundles/`, `previews/`, `caches/`)
  **without** updating `server/data-export.md`.

### Do not flag

- Columns that are clearly internal bookkeeping (replication state
  flags, backfill markers, `*_replicated_to_ch`, `processed_at`, etc.).
  These should be documented in Non-Exportable Data, not flagged as
  missing from exportable lists.
- Pure index/constraint migrations with no new data columns.

---

## 8. i18n — currency symbols are not translatable

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

## 9. Translation files — `.po` is read-only for humans

### Flag (Severity: high)

- Any modification to `server/priv/gettext/**/*.po`. Only the `tuistit`
  bot may edit `.po` files; CI will fail otherwise.
- Use of `mix gettext.extract --merge`. Only the no-`--merge` form is
  allowed in PRs.

### Do not flag

- `.pot` (template) changes — those are produced by `mix gettext.extract`
  and are expected when adding new translatable strings.

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
2. The category above is one of 1–9; if it isn't, downgrade to a
   question (`uncertain: ...`) rather than asserting a finding.
3. The severity is set: **critical** (auth bypass / cross-tenant read or
   write), **high** (likely security or correctness bug), **medium**
   (compliance / consistency gap), **low** (nice-to-have).
