defmodule Tuist.IngestRepo.Migrations.CreateTestCaseCurrentStates do
  @moduledoc """
  Pre-aggregated "latest state per test case", the read-time counterpart to the
  `test_case_states` ledger.

  `test_case_states` is an append-only, per-column-nullable ledger: each row
  sets exactly one of `state` / `is_flaky` and leaves the other NULL (see
  `20260721120000_create_test_case_states_table.exs`). Every project-scoped
  reader resolved the current value at query time with
  `argMaxIf(col, inserted_at, isNotNull(col)) GROUP BY test_case_id` over that
  ledger, and `list_test_cases/2`'s `:joined` path did so alongside a `FINAL`
  over ~2.2M `test_cases` rows behind a 512 MB grace-hash join. That
  merge-on-read scales with ledger history, not with rows returned, which is the
  root cause of the recurring ClickHouse OOM / slow-query alerts on this path
  (six PRs re-bounded memory instead of removing the work).

  This table stores the same resolution as `argMaxIf` aggregate states keyed by
  `(project_id, test_case_id)`, maintained by `test_case_current_states_mv`
  cascading off `test_case_states`. Reads finalize with
  `argMaxIfMerge(...) GROUP BY key`, combining a handful of partial states per
  key instead of folding the whole ledger.

  ## The per-column-nullable invariant is preserved

  `state` and `is_flaky` move independently and each event carries one of them.
  `argMaxIf(..., isNotNull(...))` per column keeps a `marked_flaky` event from
  clobbering a concurrent mute (and vice versa) — the whole reason the ledger
  exists. The aggregate states carry that `-If` through, so the property holds
  at the aggregate level too.

  ## Aggregate types

  `state`'s aggregate value type is `Nullable(String)`, NOT the source's
  `LowCardinality(Nullable(String))`: a LowCardinality dictionary inside a
  serialized aggregate state invites type-compat surprises across
  merges/versions, so the source is `CAST` to the plain nullable type in the
  view and the backfill. `is_flaky` keeps the source's `Nullable(Bool)` (Bool is
  fine inside the aggregate on this ClickHouse and round-trips to a real boolean,
  so readers get `true`/`false`, not `1`/`0`). The condition arg is `UInt8` (the
  `isNotNull` predicate).

  ## Ordering: table -> MV -> backfill (idempotency)

  The MV is created BEFORE the backfill so no live insert is missed. The overlap
  window (rows the MV captures live that the backfill also re-reads) is safe
  because `argMax`/`argMaxIf` is idempotent under duplicate rows with distinct
  timestamps: merging the same `(value, inserted_at)` twice takes the same max.
  Re-running the whole migration is safe for the same reason. (`inserted_at`
  ties are already nondeterministic in the ledger's own reads; this does not add
  to that.) We do not use MV `POPULATE`, which only observes later inserts.

  ## Write-path coupling (on-call note)

  This MV adds a second hop to the control-plane write path:
  `test_case_events` -> `test_case_states_mv` -> `test_case_states` ->
  `test_case_current_states_mv` -> `test_case_current_states`. With
  `materialized_views_ignore_errors = 0` (the default), an exception thrown by
  this MV during the synchronous insert pipeline propagates back and fails the
  original `test_case_events` insert, i.e. `Tuist.Tests.update_test_case/3` would
  error. The MV is deliberately trivial (per-column `argMaxIfState`, one `CAST`)
  to keep that risk near zero, but if a control-plane write outage ever
  correlates with this deploy, this cascade is the first place to look.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @max_threads 4
  @max_memory_bytes 4 * 1024 * 1024 * 1024

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_current_states (
      project_id Int64,
      test_case_id UUID,
      state AggregateFunction(argMaxIf, Nullable(String), DateTime64(6), UInt8),
      is_flaky AggregateFunction(argMaxIf, Nullable(Bool), DateTime64(6), UInt8)
    ) ENGINE = AggregatingMergeTree
    ORDER BY (project_id, test_case_id)
    """)

    # Cascades off test_case_states: the existing test_case_states_mv INSERTs
    # into test_case_states, which fires this view. It re-aggregates only the
    # inserted block into partial states; AggregatingMergeTree merges them in the
    # background. Reuses test_case_states as the single source of the
    # event->column mapping rather than duplicating the multiIf/if logic here.
    #
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_current_states_mv
    TO test_case_current_states AS
    SELECT
      project_id,
      test_case_id,
      argMaxIfState(CAST(state AS Nullable(String)), inserted_at, isNotNull(state)) AS state,
      argMaxIfState(is_flaky, inserted_at, isNotNull(is_flaky)) AS is_flaky
    FROM test_case_states
    GROUP BY project_id, test_case_id
    """)

    backfill()
  end

  # WARNING: dropping this table pulls the rug out from under every reader that
  # resolves control-plane state (`Tuist.Tests.resolve_test_case_state/2` and
  # friends). It is safe to run only once NO deployed release still reads
  # `test_case_current_states` — i.e. after the reader flip has itself been
  # reverted. Production migrations are forward-only; this exists for local dev
  # rollback. Never run it against an environment whose app pods still read the
  # table or every state read will raise "table doesn't exist".
  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_current_states_mv")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_current_states")
  end

  # The ledger is small (~129k rows against ~2.2M test cases per the source
  # table's own estimate), so a single INSERT ... SELECT is cheap — no
  # partition/project chunking like the far larger test_case_runs backfills.
  defp backfill do
    retry_on_transient_failure(fn ->
      IngestRepo.query!(
        """
        INSERT INTO test_case_current_states
        SELECT
          project_id,
          test_case_id,
          argMaxIfState(CAST(state AS Nullable(String)), inserted_at, isNotNull(state)) AS state,
          argMaxIfState(is_flaky, inserted_at, isNotNull(is_flaky)) AS is_flaky
        FROM test_case_states
        GROUP BY project_id, test_case_id
        SETTINGS max_threads = #{@max_threads},
                 max_memory_usage = #{@max_memory_bytes},
                 optimize_aggregation_in_order = 1
        """,
        %{},
        timeout: 600_000
      )
    end)
  end

  defp retry_on_transient_failure(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      message = to_string(e.message)

      transient? =
        String.contains?(message, "TABLE_IS_READ_ONLY") or
          String.contains?(message, "MEMORY_LIMIT_EXCEEDED")

      if attempts > 1 and transient? do
        Logger.warning(
          "ClickHouse returned a transient error (#{String.slice(message, 0, 80)}...); " <>
            "retrying in 5s (#{attempts - 1} attempts left)"
        )

        Process.sleep(:timer.seconds(5))
        retry_on_transient_failure(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
