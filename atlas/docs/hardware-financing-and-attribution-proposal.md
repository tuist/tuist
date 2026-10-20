# Hardware Financing and Cost Pool Proposal (Phase B)

Status: draft (round 4, after Codex round-3 review)
Owner: Pedro
Branch: `docs/hardware-inventory-proposal`
Depends on: `docs/hardware-inventory-proposal.md` (phase 1, committed)
Related contexts: `Atlas.Finance`, `Atlas.Assets`, `Atlas.Documents`
Deferred out of phase B (into phase C): per-account cost attribution, `MonthlyClose`, `AccountAllocation`, retry classification, `ValuationEvent`, multi-currency conversion, reproducible usage-measurement contract

## Scope decision

Phase B ships the **register** slice only:

1. **Financing arrangements + payments + schedules + lines** as a first-class financial register.
2. **Ownership on Asset** (`:owned | :leased | :unknown`), preserving asset identity through the purchase-option lifecycle.
3. **Cost pools + dated membership + pool overhead + pool cost decomposition** as a pure query (no attribution).

Phase C prerequisites, all needed before attribution can ship: accountant-approved accounting policy artifact, retry-cause classification in Tuist product DB, reproducible usage-measurement contract (weighted-job-milliseconds vs. runner-session-occupied-milliseconds decision, millisecond precision preserved end-to-end), monthly ECB rate snapshot pipeline.

## Delivery split (Codex-endorsed)

- **PR 1 (phase B)**: financing register + ownership.
- **PR 2 (phase B+)**: cost pools + memberships + overhead + `PoolCosts.for_month`.
- **PR 3 (phase C)**: attribution + monthly close.

PR 1 stands independently — nothing in PR 1 references pool-cost tables or attribution.

## Cardinal rules (constraints, not open questions)

1. Financing cash flow ≠ service cost. Loan principal repayment is a liability settlement, not an expense.
2. Asset identity is preserved through purchase-option exercise. No cost reset.
3. Payments are decomposed with explicit component semantics. NULL means "unknown", not zero.
4. Accounting treatment is persisted separately from legal ownership.
5. All cost calculations read dated membership. Exercising an option in October must not change September's already-recorded costs.
6. All amounts are positive magnitudes; direction is separate (matches `Finance.Transaction`).
7. All durations are milliseconds in stored fields.
8. Every long-lived invariant is DB-enforced or transactionally reload-and-verify. Warnings are never a substitute for a check.

## PR 1 (phase B) — financing register + ownership

### Context and placement

New context `Atlas.Finance.Financings` (plural, matches `Atlas.Finance.Invoices`). Public functions on `Atlas.Finance`.

Schemas: `Atlas.Finance.Financing`, `Atlas.Finance.FinancingSchedule`, `Atlas.Finance.FinancingLine`, `Atlas.Finance.FinancingPayment`.

### `Atlas.Finance.Financing`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUIDv7 | |
| `type` | string enum | `:loan | :lease_with_purchase_option | :lease_without_purchase_option`. Legal shape only. |
| `accounting_treatment` | string enum | `:capitalized | :expensed | :undetermined`. Accountant-approved. `:undetermined` on create by default. Persisted here; PR 2 defines how this filters asset reports. PR 1 does not change any existing report. |
| `treatment_evidence` | string | Free-form accountant note captured whenever `accounting_treatment` changes. Audited previous/new evidence + actor + time. |
| `provider` | string | Financing provider, for example Targo. |
| `supplier` | string | Nullable equipment supplier, for example Apple. |
| `reference` | string | |
| `disbursement_or_commencement_on` | date | Loan disbursement or lease commencement. |
| `term_months` | integer | `> 0` DB check when set. |
| `currency` | string(3) | ISO 4217. Financing-level currency. Schedule installments are in this currency. Payments' decomposition components are in the **settlement currency of the linked bank transaction**; when they differ, the payment stays `:partial`. |
| `undiscounted_commitment` | decimal(15,2) | Contract-descriptive total of scheduled payments, excluding option. Never used as a balance. |
| `initial_liability` | decimal(15,2) | Nullable. Accountant-approved discounted initial liability. Null means "not yet approved"; consumers must report unavailable, not fabricate. |
| `interest_rate` | decimal(7,4) | Annualized. Nullable. |
| `principal_amount` | decimal(15,2) | Loans only. DB check: `(type = 'loan') = (principal_amount IS NOT NULL)`. |
| `purchase_option_amount` | decimal(15,2) | Only for `:lease_with_purchase_option`. Nullable if undecided. |
| `purchase_option_available_from` | date | Nullable. |
| `status` | string enum | `:active | :paid_off | :option_exercised | :returned | :terminated` |
| `notes` | text | |
| `inserted_at`, `updated_at` | timestamps | |

Documents are attached through `FinancingDocument`, a typed join between a financing and a document. Its `kind` is one of `supplier_contract`, `financing_agreement`, `guarantee`, `invoice`, `acceptance`, `schedule`, `amendment`, or `other`. This allows one financing to retain the Apple commercial agreement, the Targo financing agreement, and its guarantee while keeping all of them connected to the same hardware allocations.

DB checks:

- `financings_undiscounted_nonneg`: `undiscounted_commitment >= 0`.
- `financings_initial_liability_nonneg`: `initial_liability IS NULL OR initial_liability >= 0`.
- `financings_term_positive`: `term_months IS NULL OR term_months > 0`.
- `financings_principal_iff_loan`: `(type = 'loan') = (principal_amount IS NOT NULL)`.
- `financings_option_amount_iff_option_lease`: `(purchase_option_amount IS NULL) OR (type = 'lease_with_purchase_option')`.
- `financings_status_option_exercised_iff_option_lease`: `status = 'option_exercised' -> type = 'lease_with_purchase_option'`.
- `financings_status_returned_iff_lease`: `status = 'returned' -> type <> 'loan'`.

### Status transition matrix

Type-parameterized. `:paid_off` is a fully terminal state for loans (no further transition legal). For leases it is an intermediate state that permits later `:option_exercised` or `:returned` or `:terminated`.

"Identity" in a cell means the operation is legal but a no-op (idempotent); it never means transitioning between two different terminal states.

| From \ To | active | paid_off | option_exercised | returned | terminated |
|---|---|---|---|---|---|
| (create) | default | | | | |
| `:loan` active | (identity) | when principal fully repaid | (illegal) | (illegal) | any time |
| `:loan` paid_off | (illegal) | (identity) | (illegal) | (illegal) | (illegal) |
| `:loan` terminated | (illegal) | (illegal) | (illegal) | (illegal) | (identity) |
| `:lease_with_purchase_option` active | (identity) | when scheduled installments fully paid | option_exercise | return_workflow | any time |
| `:lease_with_purchase_option` paid_off | (illegal) | (identity) | option_exercise | return_workflow | any time |
| `:lease_with_purchase_option` option_exercised | (illegal) | (illegal) | (identity) | (illegal) | (illegal) |
| `:lease_with_purchase_option` returned | (illegal) | (illegal) | (illegal) | (identity) | (illegal) |
| `:lease_with_purchase_option` terminated | (illegal) | (illegal) | (illegal) | (illegal) | (identity) |
| `:lease_without_purchase_option` active | (identity) | when installments paid | (illegal) | return_workflow | any time |
| `:lease_without_purchase_option` paid_off | (illegal) | (identity) | (illegal) | return_workflow | any time |
| `:lease_without_purchase_option` returned | (illegal) | (illegal) | (illegal) | (identity) | (illegal) |
| `:lease_without_purchase_option` terminated | (illegal) | (illegal) | (illegal) | (illegal) | (identity) |

`:terminated` for loans: does not touch owned assets. For leases: closes open pool memberships (PR 2) and asset assignments and moves each linked asset to `:returned_to_lessor`, matching `:returned`. The difference is intent (`:terminated` is early termination with a reason in `notes`; `:returned` is planned end-of-lease return).

### `Atlas.Finance.FinancingSchedule`

Imported installment schedule.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUIDv7 | |
| `financing_id` | FK | `on_delete: :restrict`. |
| `sequence` | integer | Unique per `(financing_id, sequence)`. |
| `due_on` | date | |
| `expected_total` | decimal(15,2) | Authoritative contractual installment total in the financing's `currency`. |
| `principal_amount` | decimal(15,2) | Nullable. |
| `interest_amount` | decimal(15,2) | Nullable. |
| `rental_amount` | decimal(15,2) | Nullable. |
| `fee_amount` | decimal(15,2) | Nullable. |
| `tax_amount` | decimal(15,2) | Nullable. |
| `option_amount` | decimal(15,2) | Nullable. |
| `deposit_amount` | decimal(15,2) | Nullable. |
| `notes` | text | |

DB checks:

- Every amount `IS NULL OR >= 0`.
- `expected_total >= 0`.
- `schedule_components_bounded`: `COALESCE(principal_amount,0) + COALESCE(interest_amount,0) + COALESCE(rental_amount,0) + COALESCE(fee_amount,0) + COALESCE(tax_amount,0) + COALESCE(option_amount,0) + COALESCE(deposit_amount,0) <= expected_total`.
- Codex round 2 pointed out this is enforceable at DB level; done.

### `Atlas.Finance.FinancingLine`

Per-asset allocation.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUIDv7 | |
| `financing_id` | FK | `on_delete: :restrict`. |
| `asset_id` | FK to `Assets.Asset` | `on_delete: :restrict`. |
| `share_bps` | integer | Basis points, 1..10000. Sum across all lines for a financing must equal 10_000 whenever any line exists. |
| `notes` | text | |

DB check: `share_bps BETWEEN 1 AND 10000`.
Unique index on `(financing_id, asset_id)`.

**Atomic allocation operation (Codex round-2 blocker)**: individual `create_financing_line` / `edit_financing_line` / `delete_financing_line` mutations do **not** exist. Only `set_financing_lines(financing_id, [{asset_id, share_bps}, ...])` exists. It:

1. Reloads the parent `financing` under `SELECT ... FOR UPDATE` — locking the parent row protects against concurrent inserts, since PostgreSQL's `FOR UPDATE` only locks retrieved rows.
2. Deletes all existing lines for the financing.
3. Inserts the new set inside the same transaction.
4. Validates `sum(share_bps) = 10_000` (or 0 if the set is empty).
5. Commits or rolls back.

A financing may temporarily exist without lines (during setup); all mutations that consume line-derived amounts (pool cost calc in PR 2, exercise, return) treat missing lines as `:incomplete` and refuse to fabricate.

### `Atlas.Finance.FinancingPayment`

One payment per matched bank transaction.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUIDv7 | |
| `financing_id` | FK | `on_delete: :restrict`. |
| `finance_transaction_id` | UUID | Unique. FK to `Finance.Transaction`. |
| `schedule_id` | UUID | Nullable FK. See composite FK below (Codex round 3). |
| `paid_on` | date | Snapshotted at match time. |
| `direction` | string enum | `:debit | :credit`. Matches `Finance.Transaction.direction`. |
| `settlement_amount` | decimal(15,2) | Positive magnitude, snapshotted. |
| `settlement_currency` | string(3) | Snapshotted. |
| `principal_amount` | decimal(15,2) | Nullable. Decomposition components in `settlement_currency`. |
| `interest_amount` | decimal(15,2) | Nullable. |
| `rental_amount` | decimal(15,2) | Nullable. |
| `fee_amount` | decimal(15,2) | Nullable. |
| `tax_amount` | decimal(15,2) | Nullable. |
| `option_amount` | decimal(15,2) | Nullable. |
| `deposit_amount` | decimal(15,2) | Nullable. |
| `unclassified_amount` | decimal(15,2) | Nullable. Explicit escape hatch for opaque installments. |
| `resolution_status` | string enum | `:resolved | :unresolved | :partial`. `:resolved` allowed **only** when the sum of known components (with NULLs coalesced to 0) exactly equals `settlement_amount` AND `unclassified_amount IS NULL OR unclassified_amount = 0`. `:partial` when a component is known but the total does not yet cover `settlement_amount`, or when a positive `unclassified_amount` is set. `:unresolved` when nothing is decomposed. |
| `notes` | text | |

DB checks (all use COALESCE so NULL evaluates as 0 inside the expression, avoiding Codex's "NULL passes the check" trap):

- Every amount `IS NULL OR >= 0`.
- `payment_components_bounded`: `COALESCE(principal_amount,0) + COALESCE(interest_amount,0) + COALESCE(rental_amount,0) + COALESCE(fee_amount,0) + COALESCE(tax_amount,0) + COALESCE(option_amount,0) + COALESCE(deposit_amount,0) + COALESCE(unclassified_amount,0) <= settlement_amount`. Enforced for **every** status.
- `payment_resolved_reconciles`: `resolution_status <> 'resolved' OR (COALESCE(...same...) = settlement_amount AND COALESCE(unclassified_amount, 0) = 0)`.
- `payment_currency_matches_transaction`: enforced by changeset by reading `Finance.Transaction.amount_currency` — not a DB check.

Cross-currency: when `settlement_currency ≠ financings.currency`, `resolution_status` is `:partial` (component sums do not roll up to the financing currency without a conversion policy, which is deferred to phase C). Documented limitation.

### Composite FK on `FinancingPayment.schedule_id` (Codex round 3 ruling)

Codex ruled open question 1: use a composite foreign key without a redundant column or trigger.

- Add `UNIQUE (financing_id, id)` to `financing_schedules`.
- `financing_payments` gets a composite FK: `FOREIGN KEY (financing_id, schedule_id) REFERENCES financing_schedules (financing_id, id)`, `MATCH SIMPLE`, allowing `schedule_id` to be null.
- No redundant column, no trigger.
- Update from a bank sync that moves a payment to a different financing must also carry `schedule_id = NULL` if the old schedule no longer applies; the FK enforces consistency at every write.

### `Atlas.Assets.Asset` amendments (phase-1 schema changes)

Additive migration:

- `ownership` string enum `:owned | :leased | :unknown`. Not null. Default `:owned` at create.
- `ownership_acquired_on` date. Nullable when `ownership <> :owned`.

**Migration compatibility (Codex round 3 correction to migration order):**

Ordering matters because adding a default before the backfill would defeat the `WHERE ownership IS NULL` guard.

1. `ALTER TABLE assets ADD COLUMN ownership varchar` (nullable, no default).
2. `ALTER TABLE assets ADD COLUMN ownership_acquired_on date` (nullable).
3. `UPDATE assets SET ownership = 'owned', ownership_acquired_on = purchased_on WHERE ownership IS NULL`.
4. `ALTER TABLE assets ALTER COLUMN ownership SET DEFAULT 'owned'`.
5. `ALTER TABLE assets ALTER COLUMN ownership SET NOT NULL`.
6. `ALTER TABLE assets ALTER COLUMN purchased_on DROP NOT NULL`.
7. `ALTER TABLE assets ADD CONSTRAINT assets_purchased_on_required CHECK (purchased_on IS NOT NULL OR ownership = 'leased') NOT VALID; ALTER TABLE assets VALIDATE CONSTRAINT assets_purchased_on_required` (in that split so validation of the existing rows happens as a separate step; can be inlined for the small table today).

Also refresh the state check constraint to include `:returned_to_lessor` (see retire/return constraint reconciliation below).

**Companion code changes in the same PR:**

- `Asset.states/0` extended with `:returned_to_lessor`.
- `Atlas.Assets.fleet_eligible?/2` returns `false` for `:returned_to_lessor` in addition to `:retired | :disposed | :lost`.
- `Atlas.Assets.book_value_report/1` SQL WHERE also excludes `:returned_to_lessor`.
- `Atlas.MCP.Serializers.Assets.asset/1`:
  - Replace `Date.to_iso8601(asset.purchased_on)` with the existing `iso_date/1` helper (nullable-safe).
  - Change the output schema's `purchased_on` type from `{"type" => "string"}` to `{"type" => ["string", "null"]}` (Codex round 3: without this the serializer output would violate its own JSON schema).
- `Atlas.MCP.Tools.CreateAsset`:
  - Add `ownership` to the input schema `properties` (Codex round 3: `additionalProperties: false` would reject it otherwise).
  - Drop `purchased_on` from `"required"` at the schema level; validation delegates to the changeset.
- **Conditional validation in `Atlas.Assets.Asset.create_changeset/2`** (Codex round 3: the phase-1 `Asset.create_changeset/2` unconditionally requires `purchased_on`; this PR modifies it to require `purchased_on` only when `ownership != "leased"`). Not `Atlas.Assets.create_changeset` (which does not exist).
- Phase-1 test additions: `insert_asset!` fixture accepts an `ownership` override; a small new test covers "leased asset without purchased_on".

### Retire vs. return constraint reconciliation (Codex round 3 blocker)

The existing phase-1 constraint `assets_retired_state_has_date` is `(state IN ('retired','disposed')) = (retired_on IS NOT NULL)`. A leased asset can already be retired (state = `:retired`, `retired_on` set) before we physically return it to the lessor. Moving that asset to `:returned_to_lessor` would leave `retired_on` set while state is not in `('retired','disposed')`, violating the constraint.

Fix: replace the equivalence with two directional implications, each expressible as a separate check:

- `assets_retired_state_has_date`: `state IN ('retired','disposed') -> retired_on IS NOT NULL` (unchanged direction).
- `assets_retired_on_allowed_states`: `retired_on IS NULL OR state IN ('retired','disposed','returned_to_lessor')` (new: retirement history preserved through subsequent return).

Migration drops the old check and adds the two new checks in one step.

Additional rules:

- `retire/2` is legal from `:returned_to_lessor` (return then write-off). Guard updated.
- `retire/2` from any state also clears `assigned_to_id` if not already null. Already the case in phase 1; asserted by a new test.
- `mark_returned_to_lessor/2`:
  - Legal source states: `:in_service | :in_storage | :in_repair | :retired`. Illegal: `:disposed | :lost | :returned_to_lessor`.
  - Clears `assigned_to_id` and closes any open `Assignment` in the same transaction (Codex round 3: explicit).
  - Preserves `retired_on` when set.
  - Preserves `pre_loss_state` and `pre_repair_state` cache values (they are not relevant to lessor return, but clearing them would lose recovery information if the asset was recovered from loss before return).

### Line replacement freeze (Codex round 3 blocker)

`set_financing_lines(financing_id, lines)` refuses to replace lines when `financing.status IN (:option_exercised, :returned, :terminated)` and `type ≠ :loan`. Loans do not have asset-linking implications on terminal transitions (see below), so `:paid_off | :terminated` for a loan allows line correction.

Rationale: once the asset ownership state has moved as a consequence of a lifecycle event, silently changing which assets the arrangement refers to would decouple the register from reality (Codex's example: exercise makes A owned, then replacing lines with B leaves A owned via an arrangement that no longer references A, and B unchanged despite now appearing in an exercised arrangement).

Terminal asset-set corrections are **deferred entirely** (Codex rounds 4 and 5). Auditing a replacement without simultaneously reconciling the affected assets' ownership would leave the register inconsistent: exercise flipped asset A to `:owned`; replacing the line with asset B would orphan A's ownership fact and leave B unchanged despite appearing in an exercised arrangement.

PR 1 offers no correction path at all after a lifecycle-terminal transition. If the accountant realizes the line set on an already-exercised, returned, or terminated arrangement was wrong, the register carries that historical fact unchanged. Whichever asset actually flipped to `:owned` retains that state via its own audit trail. Documenting the future truth is a **new arrangement**, not a correction: create a fresh `:lease_with_purchase_option` (or `:loan`) referencing the correct assets, and add a note on both arrangements cross-referencing each other. The old arrangement stays in its terminal state. No spurious `:terminated` on an already-exercised lease (illegal per the matrix); no move of already-owned assets to `:returned_to_lessor`.

Phase C introduces a paired `undo_exercise + set_lines + redo_exercise` workflow with full asset reconciliation when a real fix is genuinely needed. PR 1 does not attempt it.

### Phase-1 doc amendment (Codex round 3 correction)

Codex verified the phase-1 doc's book-value contract currently reads:

> Reporting start is `placed_in_service_on`. If the asset is not yet placed in service on the report date, `{:excluded, :not_in_service}`.
> If `state in [:retired, :disposed]` on or before the report date, `{:excluded, :off_books}`. Retirement removes the asset from the reported fleet even if computed residual is positive.
> If `state == :lost` on or before the report date, `{:excluded, :lost}` from fleet totals; still queryable individually with `{:ok, decimal, currency}` for record-keeping.

The implementation never returns any `{:excluded, _}` variant. Instead, `book_value_at/2` is pure math and returns `{:ok, decimal, currency}` or `{:error, :missing_valuation}` only; state filtering lives entirely in `book_value_report/1`.

PR 1 ships a small phase-1 doc amendment commit that:

- Replaces the three `{:excluded, ...}` sentences with a single paragraph stating the actual contract: pure math, no state check.
- Names `fleet_eligible?/2` as the eligibility predicate and lists `:retired | :disposed | :lost | :returned_to_lessor` as the excluded states.
- Adds `:returned_to_lessor` to the states table.

### Purchase-option lifecycle (identity-preserving)

Exercise workflow, one transaction, audit-after-commit:

1. Reload `financing` under `FOR UPDATE`. Reject if `type ≠ :lease_with_purchase_option` OR `status NOT IN (:active, :paid_off)` OR `purchase_option_amount IS NULL`.
2. Accept exactly one of:
   - `option_transaction_id` (a fresh, unmatched `Finance.Transaction.id`):
     - Reload the transaction under `FOR UPDATE`.
     - Reject if `Transaction.direction = :credit` (only debits fund the option strike; Codex round 3).
     - Snapshot the actual transaction fields (`amount_value` → `settlement_amount`, `amount_currency` → `settlement_currency`, `direction` → `direction`, `booked_at` → `paid_on`). Do not hardcode `:debit`.
     - Insert a new `FinancingPayment` with `option_amount = purchase_option_amount`.
   - `existing_payment_id` (an already-matched `FinancingPayment.id` on this financing):
     - Reload the payment under `FOR UPDATE` so a concurrent `edit_financing_payment_decomposition` cannot race the exercise.
     - Validate `financing_id` matches, `direction = :debit`, `option_amount = purchase_option_amount`, `settlement_currency = financings.currency` (cross-currency exercise rejected regardless of branch).
3. Cross-currency rejection: if `payment.settlement_currency ≠ financings.currency`, refuse exercise with a clear error.
4. For each `FinancingLine.asset_id`:
   - `Asset.ownership = :owned`.
   - `Asset.ownership_acquired_on = exercise_date`.
   - If `Asset.purchased_on IS NULL`, set to `exercise_date`. Never overwrite an existing purchase date.
   - `Asset.placed_in_service_on` and `Asset.acquisition_cost` are preserved.
5. `financing.status = :option_exercised`.
6. Exercise input carries an `exercise_note` text field. Stored on the exercise audit entry.

Post-exercise payment protection (Codex round 3 and 4): `edit_financing_payment_decomposition/2` runs inside a transaction that reloads the **parent `financing` under `SELECT ... FOR UPDATE`** before re-reading `financing.status` and applying the update. This serializes with a concurrent exercise: a decomposition edit prepared before exercise cannot commit after exercise has flipped status.

Once the reloaded status shows `:option_exercised`, the edit refuses to change `option_amount` away from `financings.purchase_option_amount`. Other components (unclassified, fees, etc.) remain editable so the accountant can correct the settlement split, but the strike component is pinned.

Return workflow, one transaction:

1. Reload under `FOR UPDATE`. Reject if `type = :loan` OR `status NOT IN (:active, :paid_off)`.
2. `financing.status = :returned`.
3. For each `FinancingLine.asset_id`:
   - Transition `Asset.state = :returned_to_lessor` via a new lifecycle function `Assets.mark_returned_to_lessor/2`. This function does **not** delegate to phase-1 `return_asset/2` (that requires `:in_service` and moves to `:in_storage`). Instead it directly closes any open assignment (`Assignment.close_changeset` with `returned_on = return_date`) and updates the asset row atomically.
   - Any open pool membership (introduced in PR 2) would be closed here; PR 1 does not touch memberships (they do not exist yet). PR 2's migration adds a small `Finance.Financings.on_return_close_memberships/2` hook that the return workflow calls; PR 1's return workflow just closes assignments.

Termination workflow:

- Loans: sets `status = :terminated`; no asset-side effects.
- Leases: same as return, with `:terminated` on the financing.

Paid-off transition:

- Manual for now (a `mark_paid_off/2` operation). PR 1 does not automate detection; that requires reconciled principal-to-date, which depends on payment decomposition being complete for every installment. Detection is a phase C candidate.

### Interest totals view (Codex round 2 answer to open question 1)

Arrangement detail page shows "net matched interest paid" per settlement currency, computed as `Σ interest_amount where direction=:debit - Σ interest_amount where direction=:credit`. Rows with unmatched or `:partial` cross-currency payments contribute a "cross-currency partial: N payments" note without silently omitting the arrangement.

### MCP tools (PR 1 subset)

Reads:
- `list_financings(filters, page)`
- `get_financing(id)`
- `list_financing_payments(financing_id, page)`
- `list_financing_schedules(financing_id, page)`
- `list_asset_financings(asset_id)`

Mutations (executive-only, matching phase 1):
- `create_financing(...)` — accepts type, provider, reference, dates, currency, undiscounted_commitment, and optionally the full line set.
- `edit_financing_metadata(id, ...)`
- `set_financing_accounting_treatment(id, treatment, evidence)`
- `set_financing_lines(financing_id, lines)` — atomic replacement.
- `import_financing_schedule(financing_id, installments)`
- `match_financing_payment(financing_id, finance_transaction_id, decomposition)`
- `edit_financing_payment_decomposition(payment_id, decomposition)`
- `exercise_purchase_option(financing_id, on, option_transaction_id_or_existing_payment_id, exercise_note)`
- `return_financing(id, on)`
- `mark_financing_paid_off(id, on)`
- `terminate_financing(id, on, reason)`

### Dashboard (PR 1 subset)

- `/hardware/financings` (executive-only, in the existing `live_session :executive_dashboard`): filterable list. Filters: type, status, provider.
- `/hardware/financings/:id`: detail with schedule table, matched payments with decomposition, linked assets and shares, contract document link, purchase-option details for lease-with-option, exercise/return/paid-off/terminate action buttons that open Noora modals (matching the phase-1 register modal pattern).
- `/hardware/:id` gains a "Financing" section showing linked financings and shares.

Noora patterns per phase 1: `<.filter_dropdown>`, `<.text_input type="search">`, `<.table>` with `<:col>` slots and `<.text_cell>`/`<.badge_cell>`/`<.text_and_description_cell>`, `<.modal>` with `<:trigger>` for the create-and-exercise flows.

### PR 1 tests

- Financing create, metadata edit, treatment change with evidence audit.
- Status transition matrix per type: legal and illegal transitions from each state.
- Set lines atomic: valid full set commits; partial set rolls back; concurrent set-lines against the same financing serializes via the parent lock.
- Schedule import: DB check rejects a row whose known components exceed `expected_total`.
- Payment decomposition: DB check rejects components summing above settlement for any status; `:resolved` rejected when unclassified > 0.
- Refund matching: `:credit` payment with the same decomposition schema; interest totals subtract credits.
- Cross-currency payment: forced to `:partial`; interest total flags "cross-currency partial: 1 payment".
- Exercise: identity preserved (placed_in_service_on unchanged, acquisition_cost unchanged); `purchased_on` backfilled only when null; exercise from `:paid_off` legal; exercise from `:terminated` illegal; exercise with a null strike rejected; cross-currency exercise rejected; exercise using an already-matched option payment succeeds.
- Return: `Asset.state = :returned_to_lessor`, open `Assignment` closed atomically, does **not** invoke phase-1 `return_asset/2` (asserted by not touching `:in_storage`).
- Terminate loan: does not touch assets.
- Terminate lease: identical to return.
- Migration compatibility: existing owned assets survive; `purchased_on` remains not-null for them; new leased asset without `purchased_on` accepted; `book_value_report` still excludes `:retired | :disposed | :lost` and now also `:returned_to_lessor`.
- MCP `CreateAsset`: leased asset without `purchased_on` accepted; owned asset without `purchased_on` rejected with a changeset error.

All async, following phase-1 conventions.

### PR 1 migration

Single migration `create_finance_financings_and_extend_assets`:

1. `create table financings ...` with all DB checks.
2. `create table financing_schedules ...`.
3. `create table financing_lines ...`.
4. `create table financing_payments ...`.
5. `alter table assets add ownership, ownership_acquired_on`, `drop not null on purchased_on`, `add check assets_purchased_on_required`.
6. `update assets set ownership = 'owned', ownership_acquired_on = purchased_on where ownership is null`.
7. `alter type assets state check` extended with `:returned_to_lessor`.

## PR 2 (phase B+) — cost pools + memberships + overhead + pool cost decomposition

### Cost pools

`Atlas.Finance.CostPool`: slug (unique), name, `attribution_policy` (`:consumption_minutes | :overhead_only`), `capacity_unit` (`:weighted_job_milliseconds` nullable for overhead-only pools).

`Atlas.Finance.CostPoolMembership`: dated intervals.

- Half-open interval semantics throughout: `[effective_from, effective_to)`. `effective_to = NULL` means "still active". Same-day handoff: one membership ends on day D (`effective_to = D`), the next begins on day D (`effective_from = D`). No off-by-one.
- Partial unique index on `(asset_id)` where `effective_to IS NULL`.
- Overlap invariant across all rows for the same asset enforced transactionally: `set_membership(asset_id, cost_pool_id, effective_from)` reloads **the `Asset` row** under `SELECT ... FOR UPDATE` (Codex round 2: locking the asset row prevents concurrent inserts that would slip past a lock on existing memberships).
- Backfill: idempotent Mix.Task with a `WHERE NOT EXISTS` guard so it only creates memberships for assets that have none. One-time production run; subsequently manual per-asset.

No denormalized `cost_pool_id` on `Asset` (Codex round 2: omit initially, no perf evidence to justify).

### Pool overhead

`Atlas.Finance.PoolOverhead`: label, amount, currency, cadence (`:monthly | :one_off`), `effective_from`, `effective_to`, `finance_transaction_id` (nullable). Half-open `[from, to)`.

Recognition:

- `:one_off`: recognized entirely in `effective_from`'s month.
- `:monthly`: prorated by days-in-effective-interval / days-in-month at partial-month boundaries; full amount for full months.

Double-count guard against `FinancingPayment` (Codex round 2: partial unique index across two tables is not possible; done as follows):

- Both `PoolOverhead.finance_transaction_id` and `FinancingPayment.finance_transaction_id` unique in their own tables.
- Insert paths on both tables lock the `Finance.Transaction` row under `SELECT ... FOR UPDATE`, then check for existence in the other table; reject if found.
- Test coverage asserts the invariant under concurrent inserts.

### Pool cost calculation

`Atlas.Finance.PoolCosts.for_month(pool_slug, year_month)` — **live read only**, not authoritative for closed months. Explicitly documented limitation: current ownership and treatment influence past-month reads. Phase C's `MonthlyClose` will freeze inputs; this function is for the dashboard and for phase C's assemble step, not for leadership reports directly.

Returns:

```elixir
%{
  depreciation: %{"EUR" => Decimal, ...},
  interest: %{"EUR" => Decimal, ...},
  rental_and_service: %{"EUR" => Decimal, ...},
  overhead: %{"EUR" => Decimal, ...},
  sources: %{
    assets: [{asset_id, amount, currency}, ...],
    financings: [{financing_id, kind, amount, currency}, ...],
    overheads: [{overhead_id, amount, currency}, ...]
  },
  completeness: %{
    depreciation: :complete | :missing_assets,
    interest: :complete | :missing_schedule | :treatment_undetermined,
    rental_and_service: :complete | :missing_schedule | :treatment_undetermined,
    overhead: :complete
  }
}
```

Components (Codex round 2: remove automatic lease depreciation, restrict expensed lease to service components):

- **`depreciation`**: sum of per-asset monthly straight-line depreciation for assets whose current `ownership = :owned AND valuation_treatment = :depreciable`. Leased assets under any accounting treatment contribute nothing to depreciation until phase C introduces the accountant-approved carrying-value calculation.
- **`interest`**: for financings with `accounting_treatment = :capitalized`, sum the `interest_amount` component of schedule installments due in the month, allocated to member assets via `share_bps`. `treatment_undetermined` when treatment is `:undetermined`; `missing_schedule` when the schedule row is missing but the treatment is set.
- **`rental_and_service`**: for financings with `accounting_treatment = :expensed`, sum the schedule installment components `rental + fee + tax` (**not** `principal + interest + option + deposit`, which are financing cash flow / capital lifecycle events) due in the month, allocated via `share_bps`.
- **`overhead`**: sum of `PoolOverhead` recognized in the month per the rules above.

Mid-month asset moves between pools (Codex round 2): each month is split into intervals by membership boundaries; costs are prorated by days-in-interval / days-in-month. A membership starting on the 15th of a 30-day month receives 16/30 of the depreciation for that asset.

Historical asset-fact usage: for a month `M`, the pool cost read joins on `CostPoolMembership` whose `[effective_from, effective_to)` overlaps `M`. Asset fields consumed (`ownership`, `valuation_treatment`) are read as-of-today because we do not store dated asset-fact history. This is the phase-B limitation Codex flagged as unavoidable without a full history table; phase C's snapshot fixes it authoritatively.

### PR 2 tests

- Half-open interval semantics: same-day handoff creates no overlap.
- Overlap invariant under concurrent set-membership on the same asset.
- Backfill idempotency: repeated runs no-op.
- Overhead recognition per cadence.
- Double-count guard: `PoolOverhead` and `FinancingPayment` on the same transaction refused, concurrent inserts serialize.
- Pool cost decomposition per component: depreciation for owned-only, interest for capitalized-only, rental_and_service for expensed-only excluding principal/interest/option/deposit, overhead recognized correctly.
- Mid-month move: prorated across pools by days.
- Completeness flags: `treatment_undetermined` blocks interest and rental_and_service until treatment is set; `missing_schedule` reports the shortfall without fabrication.

### PR 2 migration

Single migration `create_finance_cost_pools_and_overheads`:

1. `create table cost_pools ...`.
2. `create table cost_pool_memberships ...` with partial unique on `(asset_id)` where `effective_to IS NULL`.
3. `create table pool_overheads ...` with cadence check and unique on `finance_transaction_id`.
4. Seed the two pools (`build_farm`, `office`).

## Deferred to PR 3 (phase C)

- `MonthlyClose`, `AccountAllocation`.
- `normal_utilization_minutes` capacity policy.
- Retry-classification.
- Multi-currency ECB conversion.
- Millisecond-precise usage measurement contract (weighted job ms vs. runner session ms).
- Accountant-approved carrying-value depreciation for capitalized leases.

## Resolved decisions (Codex round 3 rulings)

1. **Composite FK**: adopted — `UNIQUE (financing_id, id)` on `financing_schedules`, composite FK from `financing_payments` with `MATCH SIMPLE`. No trigger, no redundant column.
2. **Allocation edits after matched payments**: allowed with an audited before/after line set. Freeze applies only after exercise/return/terminate lifecycle transitions (see "Line replacement freeze"). Live pool reads always use the current line set; historical accuracy is provided by phase C's snapshot.
3. **Leased asset with permanently null `purchased_on`**: accepted. UI displays a "Leased, returned to lessor" badge.
4. **Cross-currency non-option payments**: keep as `:partial`. Interest total flags "cross-currency partial: N payments".
5. **`:paid_off` lease that we neither exercise nor return**: keep in `:paid_off` until an explicit lifecycle action. Lease `:paid_off → :terminated` is a legal transition (matrix updated). Dashboard flags "lease past term without terminal action" as an attention item.
