defmodule Cache.CacheArtifactOrphanCleanupWorker do
  @moduledoc """
  Oban worker that walks `cache_artifacts` rows and deletes those whose
  on-disk file no longer exists.

  This is the symmetric counterpart to `Cache.OrphanCleanupWorker`:

    * `OrphanCleanupWorker` finds files on disk with no DB row and deletes
      the files (disk orphans).
    * This worker finds DB rows with no file on disk and deletes the rows
      (metadata orphans).

  Metadata orphans accumulate when a file is removed outside the normal
  eviction path (manual cleanup, partially-failed batch delete, older CLI
  versions that pruned files directly) or when `CacheArtifacts.delete_by_keys`
  itself fails. Over time this can grow `repo.sqlite` to tens of GB beyond
  what the files on disk justify.

  ## Safety

  Only rows whose `updated_at` is older than `@min_age_seconds` are scanned,
  mirroring `OrphanCleanupWorker`'s rule. This avoids deleting a row for an
  upload that was just buffered but where the file isn't visible on disk yet
  for this scanner (e.g., racy fs cache on a different node's view).

  ## Cursor

  The last scanned `id` is held in `Application` env. On restart the scan
  begins from 0 again — the operation is idempotent and cheap on healthy
  nodes.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  import Ecto.Query

  alias Cache.CacheArtifact
  alias Cache.Disk
  alias Cache.Repo

  require Logger

  @cursor_key :cache_artifact_orphan_cleanup_cursor
  @min_age_seconds 3_600
  @batch_size 1_000
  @default_max_duration_ms 120_000
  @default_vacuum_pages 10_000
  @default_max_deletes_per_run 10_000
  @recheck_sleep_ms 50
  @telemetry_event [:cache, :cache_artifacts, :orphan_cleanup, :complete]

  @impl Oban.Worker
  def perform(_job) do
    started_at = System.monotonic_time(:millisecond)
    deadline_ms = started_at + max_duration_ms()
    cursor = Application.get_env(:cache, @cursor_key, 0)
    delete_budget = max_deletes_per_run()

    {new_cursor, summary, _remaining_budget} =
      scan(cursor, deadline_ms, delete_budget, %{rows_checked: 0, orphans_deleted: 0})

    Application.put_env(:cache, @cursor_key, new_cursor)

    maybe_reclaim_pages(summary)
    log_summary(summary, new_cursor)
    emit_telemetry(summary, started_at)
    :ok
  end

  defp scan(cursor, _deadline_ms, 0 = _budget, summary) do
    # Per-run deletion cap reached; stop but keep the cursor so the next run
    # picks up from where we left off.
    Logger.warning("cache_artifacts orphan scan: per-run deletion cap reached")
    {cursor, summary, 0}
  end

  defp scan(cursor, deadline_ms, budget, summary) do
    if deadline_reached?(deadline_ms) do
      {cursor, summary, budget}
    else
      batch = fetch_batch(cursor)

      case batch do
        [] ->
          # Reached the end of the table — reset the cursor so the next run
          # starts over. Avoids burning CPU on a tight wrap-around loop when
          # the table is small relative to the per-run time budget.
          {0, summary, budget}

        rows ->
          {orphans, checked} = classify(rows)
          {orphans_to_delete, leftover} = Enum.split(orphans, budget)
          :ok = delete_orphans(orphans_to_delete)

          next_cursor =
            if leftover == [] do
              rows |> List.last() |> Map.fetch!(:id)
            else
              # Budget exhausted partway through the batch. Don't advance past
              # the rows we didn't get to delete — next run needs to revisit them.
              cursor
            end

          next_summary = %{
            rows_checked: summary.rows_checked + checked,
            orphans_deleted: summary.orphans_deleted + length(orphans_to_delete)
          }

          next_budget = budget - length(orphans_to_delete)

          scan(next_cursor, deadline_ms, next_budget, next_summary)
      end
    end
  end

  defp fetch_batch(cursor) do
    cutoff = DateTime.add(DateTime.utc_now(), -@min_age_seconds, :second)

    Repo.all(
      from(a in CacheArtifact,
        where: a.id > ^cursor and a.updated_at < ^cutoff,
        order_by: [asc: a.id],
        limit: ^@batch_size,
        select: %{id: a.id, key: a.key}
      )
    )
  end

  defp classify(rows) do
    Enum.reduce(rows, {[], 0}, fn %{id: id, key: key}, {orphans, checked} ->
      if orphan?(key) do
        {[id | orphans], checked + 1}
      else
        {orphans, checked + 1}
      end
    end)
  end

  # Double-checked: a row is treated as an orphan only if the file is missing
  # on *both* checks, separated by a small sleep. Protects against transient
  # ENOENT (e.g., rename in progress, kernel cache weirdness).
  defp orphan?(key) do
    path = Disk.artifact_path(key)

    if File.exists?(path) do
      false
    else
      :timer.sleep(@recheck_sleep_ms)
      not File.exists?(path)
    end
  end

  defp delete_orphans([]), do: :ok

  defp delete_orphans(ids) do
    {_count, _} = Repo.delete_all(from(a in CacheArtifact, where: a.id in ^ids))
    :ok
  end

  defp maybe_reclaim_pages(%{orphans_deleted: 0}), do: :ok

  defp maybe_reclaim_pages(_summary) do
    pages = Application.get_env(:cache, :cache_artifacts_orphan_cleanup_vacuum_pages, @default_vacuum_pages)

    case Repo.query("PRAGMA incremental_vacuum(#{pages})") do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("cache_artifacts vacuum failed: #{inspect(reason)}")
    end
  end

  defp log_summary(%{rows_checked: 0}, _cursor) do
    Logger.info("cache_artifacts orphan scan: no rows in window")
  end

  defp log_summary(%{rows_checked: checked, orphans_deleted: deleted}, cursor) do
    Logger.info(
      "cache_artifacts orphan scan: checked #{checked} rows, deleted #{deleted} orphans, cursor=#{cursor}"
    )
  end

  defp emit_telemetry(summary, started_at) do
    duration_ms = System.monotonic_time(:millisecond) - started_at

    :telemetry.execute(
      @telemetry_event,
      %{
        rows_checked: summary.rows_checked,
        orphans_deleted: summary.orphans_deleted,
        duration_ms: duration_ms
      },
      %{}
    )
  end

  defp max_duration_ms do
    Application.get_env(:cache, :cache_artifacts_orphan_cleanup_max_duration_ms, @default_max_duration_ms)
  end

  defp max_deletes_per_run do
    Application.get_env(:cache, :cache_artifacts_orphan_cleanup_max_deletes_per_run, @default_max_deletes_per_run)
  end

  defp deadline_reached?(deadline_ms) do
    System.monotonic_time(:millisecond) >= deadline_ms
  end
end
