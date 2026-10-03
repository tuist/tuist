# Hardware Inventory Proposal

Status: draft (round 2, after Codex review pass 2)
Owner: Pedro
Branch: `docs/hardware-inventory-proposal`
Related contexts: `Atlas.Finance`, `Atlas.Licenses`, `Atlas.Documents`, `Atlas.Users`, `Atlas.Audit`

## Motivation

Tuist owns a growing amount of physical hardware:

- Servers, switches, UPS units, and other gear in the data center we are building out.
- Laptops purchased for team members.

Today Atlas has no representation of any of it. Purchase invoices land in `Atlas.Finance` as anonymous cash outflows, warranty dates live in vendors' portals, and the mapping from "who has which MacBook" only exists in Pedro's head. As the fleet grows this becomes an operational and financial blind spot. We want to answer: *"what did we spend on hardware this year, and what is the current estimated book value of each device?"*, *"which laptops are past their useful life?"*, *"what warranty expires next month?"*, *"who had that laptop before it was reassigned?"*.

## How companies typically model this

Two overlapping concerns show up in every mature setup, even if they share a table:

1. **Fixed Asset Register (accounting/finance).** Per asset: acquisition date, initial cost, useful life, depreciation method, accumulated depreciation, net book value, salvage/disposal proceeds.
2. **IT Asset Management / CMDB (operational).** Serial, tag, model, specs, warranty end, current location, current holder, and history of assignments, repairs, and state changes.

References: Snipe-IT, NetBox / Nautobot, Ralph, fixed-asset modules in ERPs (Odoo, NetSuite, Xero, SAP). Companies our size collapse both into one table and split later when categories need different validation or workflows.

## Scope for phase 1

- **(A) Lightweight register (this phase).** What we own, who has it, current state, purchase evidence, per-asset estimated book value on demand.
- **(B) Deferred to later.** Slack warranty-expiry notifier, refresh-cycle alerts, monthly rollups, disposal gain/loss, historical (frozen) valuations, reconciliation widgets, restricted employee-facing view, currency normalization to a single fleet total.

Atlas is not the general ledger. Estimated book value is computed for our own reporting only. Books live in Qonto plus accounting.

## Historical reporting: explicit scope decision

Reliable point-in-time reporting requires either persisting dated lifecycle transitions (loss date, retirement date, disposal date, place-in-service date, and every backdated correction as a separate row) or restricting fleet membership queries to the current state.

**Phase 1 choice: fleet-level reports reflect the current state only.** Per-asset estimated book value is a pure function of `(acquisition_cost, salvage_value, placed_in_service_on, useful_life_months)` and a requested date, and is documented as "computed under today's assumptions". No back-dating guarantees.

Fields that make phase B (historical) additive without a schema break:

- `placed_in_service_on` (date)
- `lost_on`, `recovered_on` (dates)
- `retired_on`, `disposed_on` (dates)
- `state` (current)

When phase B ships, we add a `LifecycleTransition` table or freeze snapshots without renaming anything above.

## Domain model

New context: `Atlas.Assets`. Placed alongside `Atlas.Licenses` and `Atlas.Finance`.

### `Atlas.Assets.Asset`

Single table covering laptops, servers, network gear, monitors, UPS units, and peripherals. Category-specific fields live in a JSONB `specs` map.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUIDv7 | Via `Atlas.Schema`. |
| `asset_tag` | string | Internal tag. Whitespace-trimmed; empty becomes null. Assigned/corrected through `edit_metadata/3`. Partial unique index where not null. Stable after retirement. |
| `serial_number` | string | Manufacturer serial. Whitespace-trimmed. |
| `manufacturer` | string | **Required when `serial_number` is set** (changeset + DB check `serial_manufacturer_present`). |
| `model` | string | |
| `name` | string | Human label. |
| `category` | string enum | `:laptop | :desktop | :server | :network_switch | :router | :ups | :monitor | :peripheral | :other` |
| `specs` | jsonb (default `{}`) | Free-form. Example keys documented in module doc. |
| `purchased_on` | date | Required. |
| `placed_in_service_on` | date | Nullable. Set only via `place_in_service/2`. Depreciation clock starts here. |
| `acquisition_cost` | decimal(15,2) | **Matches Finance precision/scale exactly** (`Finance.Transaction.amount_value` is `precision: 15, scale: 2`). This is the per-asset **allocated** cost, not the transaction total. Required. |
| `acquisition_currency` | string(3) | ISO 4217. Validated in the changeset by `Cldr.Currency.known_currency?/1`. `Atlas.Accounts.Amounts.normalize_currency/1` only uppercases; it does not reject unknown codes, so we validate explicitly. |
| `useful_life_months` | integer | **Snapshotted at creation** from a category default (laptops 36, desktops 48, servers 60, network 60, monitors 60, UPS 60, peripherals 24, other 36). Overridable per asset. DB check `useful_life_positive`: `useful_life_months > 0`. |
| `salvage_value` | decimal(15,2) | Default `0`. DB checks: `salvage_nonneg` (>=0), `salvage_bounded` (`salvage_value <= acquisition_cost`). |
| `valuation_treatment` | string enum | `:depreciable | :fully_expensed | :unknown`. Set explicitly at creation. `:fully_expensed` short-circuits the book-value function to `salvage_value` from `placed_in_service_on`; `:unknown` returns `{:error, :missing_valuation}` from `book_value_at/2`. Replaces the deferred automatic threshold. |
| `state` | string enum | `:in_service | :in_storage | :in_repair | :retired | :disposed | :lost` |
| `location` | string enum | `:data_center | :office | :home | :in_transit | :other` |
| `location_detail` | string | Free-form. |
| `warranty_end_on` | date | Nullable. Read-write via `edit_metadata` (audited corrections) and `record_warranty_extension` (atomic update + event). |
| `assigned_to_id` | UUID | FK to `users`, `on_delete: :nilify_all`. Nullable. Denormalized cache of the open assignment. |
| `rack_position` | jsonb | Nullable. |
| `finance_transaction_id` | UUID | FK to `Atlas.Finance.Transaction`, `on_delete: :nilify_all`. Non-unique. Optional. |
| `finance_invoice_id` | UUID | FK to `Atlas.Finance.Invoice`, `on_delete: :nilify_all`. Non-unique. Optional. |
| `purchase_document_id` | UUID | FK to `Atlas.Documents.Document`, `on_delete: :nilify_all`. Non-unique. Changeset validates `document.status in ~w(uploaded processing ready)`; `"pending_upload"` and `"failed"` are rejected. (`Atlas.Documents` uses `status`, not `state`; valid values are `pending_upload | uploaded | processing | ready | failed`.) |
| `vendor` | string | Free-form. |
| `lost_on` | date | Nullable. Set only via `mark_lost/2`; overwritten on repeat loss. |
| `recovered_on` | date | Nullable. Set only via `recover/2`. Cleared by `mark_lost/2` on a subsequent loss so the DB check `recovered_after_lost` cannot be violated by a second loss. Only the most recent loss/recovery pair is preserved on the asset row; the full history lives in audit and (phase B) in a lifecycle transitions table. |
| `pre_loss_state` | string enum | Nullable. Snapshot of the asset's state immediately before `mark_lost/2`. `recover/2` restores from this value and then clears it. Persisting this on the asset removes the "recovery has no authoritative destination" ambiguity. |
| `retired_on` | date | Nullable. Set only via `retire/2` or `dispose/2`. |
| `disposed_on` | date | Nullable. Set only via `dispose/2`. |
| `disposal_proceeds` | decimal(15,2) | Nullable. |
| `disposal_currency` | string(3) | Nullable. |
| `notes` | text | |
| `inserted_at`, `updated_at` | timestamps | |

Named DB check constraints (so changesets can translate them into user-visible errors):

- `useful_life_positive`: `useful_life_months > 0`
- `acquisition_cost_nonneg`: `acquisition_cost >= 0`
- `salvage_nonneg`: `salvage_value >= 0`
- `salvage_bounded`: `salvage_value <= acquisition_cost`
- `serial_manufacturer_present`: `serial_number IS NULL OR manufacturer IS NOT NULL`
- `disposal_currency_when_proceeds`: `disposal_proceeds IS NULL OR disposal_currency IS NOT NULL`
- `retired_state_has_date`: `(state IN ('retired','disposed')) = (retired_on IS NOT NULL)`
- `disposed_state_has_date`: `(state = 'disposed') = (disposed_on IS NOT NULL)`
- `disposal_after_retirement`: `disposed_on IS NULL OR (retired_on IS NOT NULL AND disposed_on >= retired_on)`
- `in_service_has_place_date`: `state <> 'in_service' OR placed_in_service_on IS NOT NULL`
- `recovered_after_lost`: `recovered_on IS NULL OR (lost_on IS NOT NULL AND recovered_on >= lost_on)`

Indexes:

- Partial unique on `asset_tag` where not null.
- Partial unique on `(manufacturer, serial_number)` where `serial_number` is not null. Manufacturer is required in that case (see check constraint), so this cannot admit duplicates with null manufacturer.
- Btree: `assigned_to_id`, `state`, `category`, `finance_transaction_id`, `finance_invoice_id`, `purchase_document_id`.

`update_asset/2` does not exist. Metadata is edited through `edit_metadata/3`, which explicitly does **not** cast `assigned_to_id`, `state`, `retired_on`, `disposed_on`, `lost_on`, `recovered_on`, `disposal_proceeds`, `disposal_currency`, `placed_in_service_on`, or `warranty_end_on` extensions. Warranty-end edits go through `edit_metadata` for typo corrections (audited with previous and new values); an actual paid-for extension goes through `record_warranty_extension` (see below). Backdated lifecycle corrections go through `correct_lifecycle/3`, which is fully audited and DB-locked and preserves ordering invariants.

### `Atlas.Assets.Assignment`

Custody intervals.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUIDv7 | |
| `asset_id` | FK | `on_delete: :restrict`. |
| `user_id` | FK | `on_delete: :restrict`. Not nullable. Storage/DC is represented on the asset itself, not by a phantom assignment. |
| `user_label_snapshot` | string | Cached `"First Last <email>"` at assignment time. Because `on_delete: :restrict` blocks user hard-deletion outright, this snapshot is for post-anonymization work in phase B; it is not a substitute for hard-delete support today. |
| `assigned_on` | date | |
| `returned_on` | date | Nullable while open. DB check `returned_after_assigned`: `returned_on IS NULL OR returned_on >= assigned_on`. |
| `notes` | text | |
| `inserted_at`, `updated_at` | timestamps | |

Indexes:

- Partial unique on `asset_id` where `returned_on IS NULL` (one open assignment per asset).
- Btree: `asset_id`, `user_id`.

Invariant, stated correctly: for any asset with a non-null `assigned_to_id`, exactly one open `Assignment` row exists whose `user_id` equals it. A closed assignment for that user can still exist (the same user held the asset previously). Lifecycle functions maintain this invariant inside a single transaction; a background reconciliation job (phase B) can assert it periodically.

Overlap policy: `assign`, `return_asset`, and `correct_lifecycle` reject any change that would produce two intervals overlapping (strictly, `[assigned_on, returned_on || +inf)`) for the same asset. Same-day handoffs are allowed: an assignment ending on `D` and another starting on `D+1` do not overlap; two starting on the same `D` do. Overlap detection runs against the freshly locked row set.

### `Atlas.Assets.Event`

Physical observations that are not custody or lifecycle transitions.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUIDv7 | |
| `asset_id` | FK | `on_delete: :restrict`. |
| `event_type` | string enum | `:repaired | :warranty_extended | :incident | :note` |
| `occurred_on` | date | |
| `notes` | text | |
| `expenditure` | decimal(15,2) | Nullable. Set for `:repaired`, `:warranty_extended`. |
| `expenditure_currency` | string(3) | Nullable. Required when `expenditure` is set (DB check). |
| `finance_transaction_id` | UUID | Nullable, `on_delete: :nilify_all`. |
| `previous_warranty_end_on` | date | Only for `:warranty_extended`. |
| `new_warranty_end_on` | date | Only for `:warranty_extended`. |
| `client_reference` | string | Optional caller-supplied idempotency key, e.g. a Slack action id. Partial unique on `(asset_id, client_reference)` where `client_reference` is not null. Callers who want at-most-once retries pass one; callers who do not can generate duplicates and manually delete. See "Retries" below. |
| `inserted_at`, `updated_at` | timestamps | |

DB check `expenditure_currency_when_amount`: `expenditure IS NULL OR expenditure_currency IS NOT NULL`.
DB check `warranty_ext_dates`: `event_type <> 'warranty_extended' OR (previous_warranty_end_on IS NOT NULL AND new_warranty_end_on IS NOT NULL AND new_warranty_end_on >= previous_warranty_end_on)`.

`record_warranty_extension/3` atomically updates `Asset.warranty_end_on` and inserts the event inside one transaction. The event captures previous and new dates so audit is meaningful.

Retries and idempotency: `Atlas.Audit.record/3` tolerates changeset error tuples but does not catch raised database errors and does not guarantee an enclosing transaction remains usable. Assignment and event rows are the source of truth. `client_reference` gives callers (workers, MCP retries) a safe way to avoid duplicates; without it, the caller is responsible for de-duplication.

## Context module (`Atlas.Assets`)

Every mutating function runs inside `Repo.transaction/1`, reloads the asset with `SELECT ... FOR UPDATE`, validates the transition against the reloaded row, writes changes, and returns. **The audit call is made after the transaction returns `{:ok, _}`**, matching the actual pattern used at `lib/atlas/licenses.ex:113`. The audit metadata includes previous state/holder/date, new state/holder/date, `path: "/hardware/#{id}"`, and the actor/interface pulled from process context established by the LiveView mount (`Atlas.Audit.put_context/1`) or MCP server (`Atlas.Audit.with_context/2`). Domain functions do **not** attempt to derive interface from `Process.info`; workers must set their own context explicitly.

```elixir
# Creation and metadata
create_asset(attrs)
edit_metadata(asset, attrs, opts)                    # non-lifecycle fields incl. warranty_end_on corrections
correct_lifecycle(asset, corrections, opts)          # audited manual correction; preserves invariants

# Lifecycle (state-machine functions, one per transition)
place_in_service(asset, on: date, opts)
assign(asset, user, on: date, notes: notes, opts)
return_asset(asset, on: date, notes: notes, opts)
mark_in_repair(asset, on: date, notes: notes, opts)
mark_repaired(asset, on: date, notes: notes, opts)
mark_lost(asset, on: date, notes: notes, opts)
recover(asset, on: date, notes: notes, opts)
retire(asset, on: date, notes: notes, opts)
dispose(asset, on: date, proceeds: nil, currency: nil, notes: notes, opts)

# Events
record_repair(asset, attrs, opts)
record_incident(asset, attrs, opts)
record_warranty_extension(asset, attrs, opts)        # atomically updates warranty_end_on + inserts event
record_note(asset, attrs, opts)

# Reads (all paginated via Flop, all preload used associations)
get_asset!(id)
list_assets(params)                                   # filters: category, state, holder_id, location, has_open_warranty
list_assignments(asset, params)                       # paginated
list_events(asset, params)                            # paginated

# Derived (pure)
book_value_at(asset, on: date)                        # {:ok, %Decimal{}, currency} | {:error, reason}
fleet_eligible?(asset, on: date)                      # false when state in [:retired, :disposed, :lost]
book_value_report(scope, on: date)                    # groups by (category, currency); current-state only
```

`book_value_at/2` is pure math independent of state. `fleet_eligible?/2` gates inclusion in fleet reports (excludes `:retired | :disposed | :lost`; individual per-asset queries still return the computed value for record-keeping). Splitting them removes the earlier contradiction where "lost" was both queryable and excluded.

### Book-value contract

```
def book_value_at(%Asset{valuation_treatment: :unknown}, _), do: {:error, :missing_valuation}
def book_value_at(%Asset{valuation_treatment: :fully_expensed} = a, on: date) do
  if is_nil(a.placed_in_service_on) or Date.before?(date, a.placed_in_service_on),
    do: {:ok, a.acquisition_cost, a.acquisition_currency},
    else: {:ok, a.salvage_value, a.acquisition_currency}
end
def book_value_at(%Asset{valuation_treatment: :depreciable} = a, on: date), do: ...
```

Depreciable arithmetic (all `Decimal`, no floats, `Decimal.Context` rounding half-up, scale 2 to match column):

```
if placed_in_service_on is nil or date < placed_in_service_on:
    {:ok, acquisition_cost, currency}       # not yet in service; full cost
depreciable = acquisition_cost - salvage_value
elapsed_months = months_elapsed(placed_in_service_on, date)  # see convention below
elapsed_months = min(elapsed_months, useful_life_months)
monthly = depreciable / useful_life_months                    # not rounded here
accumulated = monthly * elapsed_months
# rounding: accumulated is rounded to scale 2 with :half_up.
# final-period true-up: if elapsed_months == useful_life_months, accumulated = depreciable exactly.
nbv = acquisition_cost - accumulated
{:ok, nbv, currency}
```

Convention: **pure anniversary counting**. Single formula:

```
raw_months  = (date.year - s.year) * 12 + (date.month - s.month)
day_adjust  = if date.day < min(s.day, days_in(date.year, date.month)), do: -1, else: 0
elapsed     = max(raw_months + day_adjust, 0)
elapsed     = min(elapsed, useful_life_months)
```

The `min(s.day, days_in(date.year, date.month))` clamp handles months shorter than the placement day (Jan 31 -> Feb 28, Mar 30 -> Feb 28) so an anniversary always lands on the last valid day of a shorter month. No half-month rule. No calendar-vs-anniversary hybrid. `elapsed = k` means "the k-th full anniversary of `s` has been reached".

Worked examples (documented in the module and tested):

- `placed_in_service_on = 2026-03-20`, `useful_life_months = 36`, `acquisition_cost = 3600.00`, `salvage_value = 0`.
  - `book_value_at(2026-03-19)` -> pre-service, `{:ok, 3600.00, currency}`.
  - `book_value_at(2026-03-20)` -> elapsed 0; `{:ok, 3600.00, currency}`.
  - `book_value_at(2026-04-19)` -> elapsed 0 (day 19 < day 20); `{:ok, 3600.00, currency}`.
  - `book_value_at(2026-04-20)` -> elapsed 1; `{:ok, 3500.00, currency}`.
  - `book_value_at(2029-03-19)` -> elapsed 35; `{:ok, 100.00, currency}`.
  - `book_value_at(2029-03-20)` -> elapsed 36 = useful_life_months; final-period true-up applies; `{:ok, 0.00, currency}`.
  - `book_value_at(2029-04-15)` -> elapsed clamped to 36; `{:ok, 0.00, currency}`.
- Short-month edge cases with `placed_in_service_on = 2026-01-31`:
  - `book_value_at(2026-02-27)` -> day_adjust = -1 (27 < min(31, 28) = 28); elapsed 0.
  - `book_value_at(2026-02-28)` -> day_adjust = 0 (28 >= 28); elapsed 1.
  - `book_value_at(2026-03-30)` -> day_adjust = -1 (30 < 31); elapsed 1.
  - `book_value_at(2026-03-31)` -> elapsed 2.

`days_in/2` uses `Date.days_in_month/1`.

## Lifecycle transition matrix

| From \ To         | in_service                            | in_storage                        | in_repair         | lost         | retired            | disposed     |
|-------------------|---------------------------------------|-----------------------------------|-------------------|--------------|--------------------|--------------|
| (creation)        | `create_asset` when `placed_in_service_on` and no holder | default at creation | -                 | -            | -                  | -            |
| in_storage        | `assign` (also sets `placed_in_service_on` if still null); or explicit `place_in_service` (no holder) | (identity) | `mark_in_repair` | `mark_lost` | `retire`           | -            |
| in_service        | `assign` when no open assignment       | `return_asset` (closes open assignment) | `mark_in_repair`  | `mark_lost` | `retire`           | -            |
| in_repair         | `mark_repaired` (if `pre_repair_state == :in_service`) | `mark_repaired` (if `pre_repair_state == :in_storage`) | (identity) | `mark_lost` | `retire`           | -            |
| lost              | `recover` (if `pre_loss_state == :in_service`) | `recover` (if `pre_loss_state == :in_storage`) | `recover` (if `pre_loss_state == :in_repair`) | (identity)   | `retire` (write-off) | -            |
| retired           | -                                     | -                                 | -                 | -            | (identity)         | `dispose`    |
| disposed          | -                                     | -                                 | -                 | -            | -                  | (terminal)   |

Rules that supplement the matrix:

- **Creation.** Default state is `:in_storage`. `create_asset` optionally sets `placed_in_service_on` in the same call to start `:in_service` (only allowed without a holder; combine with `assign` for the held case).
- **Assign.** Legal from `:in_storage` and from `:in_service` (when there is no open assignment). If `placed_in_service_on` is null, `assign` sets it to the same date atomically. There is no separate `place_and_assign` function; `assign` covers the case.
- **Return.** Legal from `:in_service`. Closes the open assignment; new state is `:in_storage`.
- **Repair.** Legal from `:in_storage` and `:in_service`; open assignment (if any) stays open through repair. `mark_in_repair` snapshots the current state into a nullable `pre_repair_state` cache on the asset (mirrors `pre_loss_state`). `mark_repaired` restores from `pre_repair_state` and clears it. The invariant guaranteed by `mark_in_repair` ensures `pre_repair_state` is always set on an asset in `:in_repair`. This is the authoritative rule; the matrix cells reference `pre_repair_state`, not "held before".
- **Loss.** Legal from any non-terminal, non-lost state. `mark_lost` snapshots current state into `pre_loss_state`, sets `lost_on`, clears any `recovered_on`, and moves to `:lost`. The open assignment stays open until `recover` or `retire`.
- **Recovery.** Legal only from `:lost`. `recover` sets `recovered_on`, moves to `pre_loss_state`, then clears `pre_loss_state`. `pre_loss_state` must be set (invariant guaranteed by `mark_lost`).
- **Retire.** Legal from any state (including `:lost`). Closes any open assignment. Sets `retired_on`.
- **Dispose.** Legal only from `:retired`. Sets `disposed_on` (and optional proceeds).
- Future-dated transitions are rejected in phase 1.

The `pre_repair_state` column addition (nullable string enum, snapshot of state before `mark_in_repair`, cleared by `mark_repaired`) is treated as part of the schema section above; listed here to keep the lifecycle rules self-contained.

## Cross-context links

- `Atlas.Finance.Transaction` and `Atlas.Finance.Invoice`: optional evidence, non-unique, never rewrite `acquisition_cost`.
- `Atlas.Documents.Document`: `status in ~w(uploaded processing ready)` allowed.
- `Atlas.Users.User`: `Assignment.user_id` `:restrict` blocks hard-delete (acceptable in phase 1; users are not hard-deleted today). Future anonymization uses `user_label_snapshot`.

Finance or document deletion never cascades into deleting hardware.

## Dashboard

Routes under `/hardware`, placed in the existing executive `live_session` alongside `/finance`, `/licenses`, `/documents`. Non-executive access is denied by the shared session policy; tests assert the denial.

- `HardwareLive.Index` - Flop-paginated, filter by category/state/holder/location. Counts by state.
- `HardwareLive.Show` - detail with paginated assignment timeline and event log, computed book value, warranty, evidence links.
- `HardwareLive.Form` - create/edit metadata.
- Lifecycle actions are individual confirm-flows on `Show`, each calling one context function.

Uses `data-part` styling per AGENTS.md.

## MCP tools

Registered under a dedicated `Atlas.MCP.Server` tool group (declared, not defaulted). All tools call `Atlas.MCP.Tool.authorize_executive/2` matching Licenses / Finance / Documents. `authorize_executive` verifies role only; there is no human-in-the-loop confirmation.

Reads:

- `list_assets(filters, page)` (filters include `holder_id` covering the earlier `list_assets_assigned_to` need)
- `get_asset(id)`
- `list_asset_assignments(asset_id, page)`
- `list_asset_events(asset_id, page)`
- `get_fleet_summary(on)`
- `get_asset_book_value(asset_id, on)`

Mutations:

- `create_asset(...)`
- `edit_asset_metadata(asset_id, changes)`
- `correct_asset_lifecycle(asset_id, corrections)`
- `place_asset_in_service(asset_id, on)`
- `assign_asset(asset_id, user_id, on, notes)`
- `return_asset(asset_id, on, notes)`
- `mark_asset_in_repair(asset_id, on, notes)`
- `mark_asset_repaired(asset_id, on, notes)`
- `mark_asset_lost(asset_id, on, notes)`
- `recover_asset(asset_id, on, notes)`
- `retire_asset(asset_id, on, notes)`
- `dispose_asset(asset_id, on, proceeds, currency, notes)`
- `record_asset_repair(asset_id, occurred_on, expenditure, currency, transaction_id, notes, client_reference)`
- `record_asset_incident(asset_id, occurred_on, notes, client_reference)`
- `record_asset_warranty_extension(asset_id, occurred_on, previous_warranty_end_on, new_warranty_end_on, expenditure, currency, transaction_id, notes, client_reference)`
- `record_asset_note(asset_id, occurred_on, notes, client_reference)`

## Migration plan

Single migration `create_assets`, `mix ecto.gen.migration create_assets`. Creates `assets`, `asset_assignments`, `asset_events` in one transaction. Enums as strings. All indexes, named DB checks, and FKs declared with `on_delete` above. Backfilling the initial handful goes through a separate rerunnable `Mix.Task` that dry-runs by default and prints the intended inserts. `priv/repo/seeds.exs` gets an idempotent block with 2-3 example assets for dev, per AGENTS.md.

## Tests

- Async unit tests for pure functions: `book_value_at` covering all branches (`unknown`, `fully_expensed`, `depreciable`, pre-service, post-life, worked example above), month-elapsed boundaries, decimal arithmetic and final-period true-up.
- Async context tests per lifecycle transition, including every rejected transition from every state, transaction rollback on inner failure, overlapping assignments, backdated overlaps via `correct_lifecycle`, duplicate `serial_number` and `asset_tag`, deletion behaviour for each FK, mixed-currency fleet reports.
- Async LiveView tests: `Index` filters, `Show` timeline, one lifecycle confirm-flow, non-executive access denial for each route.
- MCP tests round-trip through the domain and assert executive-only authorization.
- Fixtures use `System.unique_integer` for `serial_number`, `asset_tag`, `name`.
- Idempotency test: two identical `record_repair` calls with the same `client_reference` produce one event; without a `client_reference` produce two.
- No `Application.put_env`. Configurable behaviour (none in phase 1) would go behind an `Assets.Config` seam stubbed with Mimic, mirroring `Licenses.Config`.
- `mix precommit` and the required browser screenshots run before the implementation PR is opened.

## Explicit non-goals (phase 1)

- Slack warranty-expiry notifier and refresh-cycle alerts.
- Historical (frozen) valuations, monthly `DepreciationSnapshot`, disposal gain/loss reporting.
- Reconciliation widget for finance-link discrepancies.
- Automatic peripheral-expense threshold. Replaced by explicit `valuation_treatment`.
- Restricted employee-facing "my equipment" surface.
- Polymorphic category tables, state-machine dependency, event sourcing, rack topology / power port modeling, consumable quantities, multi-payment allocation, generic attachment framework.
- Automated asset creation from extracted invoice line items. Extraction can assist reviewed entry; it does not write.
- Multi-currency normalization to a single EUR fleet total.
- Automatic user hard-delete support (blocked by FK; anonymization is phase B work).

## Open questions retained for review

None. Codex's pass-2 recommendations for the five previously open questions are adopted verbatim above:

1. Warranty edits: `edit_metadata` audits typo corrections; `record_warranty_extension` handles paid-for extensions atomically.
2. Peripheral threshold: dropped in favour of explicit `valuation_treatment`.
3. Reconciliation widget: dropped.
4. Current equipment: read via `list_assets(holder_id: user.id)`.
5. Dashboard prefix: `/hardware`, `HardwareLive`.
