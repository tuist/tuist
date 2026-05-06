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
`Enum.each`, `Enum.flat_map`, `Enum.filter`, `Enum.reduce`, `for`, or
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
