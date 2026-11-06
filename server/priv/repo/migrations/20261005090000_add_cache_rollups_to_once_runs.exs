defmodule Tuist.Repo.Migrations.AddCacheRollupsToOnceRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @page_size 500

  @moduledoc """
  Moves the last per-action and per-cache-event aggregates the Once cache
  analytics need onto `once_runs`, so the Overview and Cache pages read one row
  per run instead of joining every action and cache event in the period.

  `cached_action_ms_total` and `executed_action_ms_total` are the summed
  `duration_ms` of a run's non-`_phase` actions split by `was_cached`, and
  `cache_event_count` is the number of `once_cache_events` rows. Existing runs
  are backfilled one run per transaction, so the backfill holds a single run
  lock at a time: it cannot hold up ingestion of other runs, and it cannot
  deadlock with a statement that locks several runs, such as the stale-run
  expiry.

  Pods still running the previous release keep projecting events without
  these columns until the rollout finishes. Runs they touch are recounted when
  they finalize, and by `Tuist.OnceEvents.recount_recent_cache_rollups/1` from
  the hourly stale-run sweep when an old pod finalized them.
  """

  def up do
    # PostgreSQL 11+ adds a column with a constant default without rewriting
    # the table, so this is a catalog change under a brief ACCESS EXCLUSIVE
    # lock on a table of a few thousand rows.
    alter table(:once_runs) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :cached_action_ms_total, :bigint, default: 0, null: false
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :executed_action_ms_total, :bigint, default: 0, null: false
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :cache_event_count, :bigint, default: 0, null: false
    end

    flush()

    backfill(nil)
  end

  def down do
    # Rolling back means the code that reads these columns is gone too.
    alter table(:once_runs) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :cached_action_ms_total
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :executed_action_ms_total
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :cache_event_count
    end
  end

  defp backfill(after_id) do
    %{rows: rows} =
      case after_id do
        nil ->
          repo().query!("SELECT id FROM once_runs ORDER BY id LIMIT $1", [@page_size])

        id ->
          repo().query!("SELECT id FROM once_runs WHERE id > $1 ORDER BY id LIMIT $2", [
            id,
            @page_size
          ])
      end

    ids = Enum.map(rows, fn [id] -> id end)

    if ids != [] do
      Enum.each(ids, fn id -> {:ok, _} = repo().transaction(fn -> backfill_run(id) end) end)
      backfill(List.last(ids))
    end
  end

  # The run row is locked before its sums are read. Every ingest inserts its
  # action or cache event and increments the run in one transaction, so one
  # that committed first is in the sums and one still in flight waits here and
  # lands after. An UPDATE on its own reads its snapshot first and could
  # overwrite an increment committed before it reached the row.
  defp backfill_run(id) do
    repo().query!("SELECT id FROM once_runs WHERE id = $1 FOR UPDATE", [id], log: false)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    repo().query!(
      """
      UPDATE once_runs r
      SET
        cached_action_ms_total = coalesce((
          SELECT sum(a.duration_ms) FROM once_actions a
          WHERE a.once_run_id = r.id AND a.was_cached AND a.capability <> '_phase'
        ), 0),
        executed_action_ms_total = coalesce((
          SELECT sum(a.duration_ms) FROM once_actions a
          WHERE a.once_run_id = r.id AND NOT a.was_cached AND a.capability <> '_phase'
        ), 0),
        cache_event_count = (
          SELECT count(*) FROM once_cache_events e WHERE e.once_run_id = r.id
        )
      WHERE r.id = $1
      """,
      [id],
      # One line per run would bury the rest of the migration output.
      log: false
    )
  end
end
