defmodule Tuist.IngestRepo.Migrations.BackfillArtifactsFromPostgres do
  @moduledoc """
  Backfills the ClickHouse `artifacts` table from PostgreSQL.

  Runs as a long-lived migration. The CH `artifacts` table uses
  `ReplacingMergeTree(updated_at)` keyed on `(bundle_id, id)`, so re-running
  this migration after a partial completion is idempotent — duplicates are
  collapsed on background merges.

  Pagination uses a UUIDv7 cursor on `id`. The PG `artifacts` table has the
  primary key index on `id` and IDs are time-ordered (UUIDv7), so each batch
  is an index seek + sequential range scan over the heap.

  The cursor is persisted in the PG `migration_cursors` table so that a
  killed migration resumes from the last committed batch on the next deploy
  rather than restarting from scratch.
  """

  use Ecto.Migration

  alias Tuist.Bundles.Artifact
  alias Tuist.IngestRepo
  alias Tuist.Repo

  import Ecto.Query

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @cursor_key "artifacts_clickhouse_backfill"
  @batch_size 250_000
  # No throttle — we are reading PG, not mutating it. CH ingestion is the
  # only side effect, and CH handles bulk inserts comfortably.
  @throttle_ms 0
  @start_cursor "00000000-0000-0000-0000-000000000000"

  @ch_types %{
    id: :uuid,
    bundle_id: :uuid,
    artifact_type:
      "Enum8('directory' = 0, 'file' = 1, 'font' = 2, 'binary' = 3, 'localization' = 4, 'asset' = 5, 'unknown' = 6)",
    path: :string,
    size: :i64,
    shasum: :string,
    artifact_id: {:nullable, :uuid},
    inserted_at: "DateTime64(6)",
    updated_at: "DateTime64(6)"
  }

  def up do
    # The PG repo is not started during ClickHouse migrations.
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    cursor = load_cursor() || @start_cursor
    Logger.info("Backfilling artifacts to ClickHouse, resuming from id=#{cursor}")

    backfill(cursor)
  end

  def down do
    :ok
  end

  defp backfill(cursor) do
    case fetch_batch(cursor) do
      [] ->
        Logger.info("Artifact backfill complete")
        :ok

      rows ->
        IngestRepo.insert_all("artifacts", rows, types: @ch_types)
        next_cursor = rows |> List.last() |> Map.fetch!(:id)
        persist_cursor(next_cursor)

        Logger.info("Backfilled #{length(rows)} artifacts, next cursor=#{next_cursor}")
        if @throttle_ms > 0, do: Process.sleep(@throttle_ms)

        backfill(next_cursor)
    end
  end

  defp fetch_batch(cursor) do
    # Disable PG's server-side statement_timeout for this connection. Each
    # batch is a bounded LIMIT query, but the safety net of `timeout: :infinity`
    # below only covers Ecto's pool timeout, not PG's statement_timeout. The
    # original [#10477](https://github.com/tuist/tuist/pull/10477) hit
    # statement_timeout precisely here.
    Repo.query!("SET LOCAL statement_timeout = 0", [])

    query =
      from(a in Artifact,
        where: a.id > ^cursor,
        order_by: [asc: a.id],
        limit: @batch_size,
        select: %{
          id: a.id,
          bundle_id: a.bundle_id,
          artifact_type: a.artifact_type,
          path: a.path,
          size: a.size,
          shasum: a.shasum,
          artifact_id: a.artifact_id,
          inserted_at: a.inserted_at,
          updated_at: a.updated_at
        }
      )

    rows = Repo.all(query, timeout: :infinity, log: false)
    Enum.map(rows, &normalize_row/1)
  end

  # PG's `artifact_type` is an `Ecto.Enum` (atom on read); CH expects the
  # string label of the Enum8. Timestamps are `:utc_datetime` in PG (second
  # precision) and `DateTime64(6)` in CH; cast to NaiveDateTime with
  # microsecond precision for the wire format.
  defp normalize_row(row) do
    %{
      row
      | artifact_type: Atom.to_string(row.artifact_type),
        inserted_at: to_naive_us(row.inserted_at),
        updated_at: to_naive_us(row.updated_at)
    }
  end

  defp to_naive_us(%DateTime{} = dt) do
    dt |> DateTime.to_naive() |> Map.update!(:microsecond, fn {value, _} -> {value, 6} end)
  end

  defp to_naive_us(%NaiveDateTime{} = ndt) do
    Map.update!(ndt, :microsecond, fn {value, _} -> {value, 6} end)
  end

  defp load_cursor do
    case Repo.query!(
           "SELECT value FROM migration_cursors WHERE key = $1",
           [@cursor_key]
         ) do
      %{rows: [[value]]} -> value
      _ -> nil
    end
  end

  defp persist_cursor(value) do
    Repo.query!(
      """
      INSERT INTO migration_cursors (key, value, inserted_at, updated_at)
      VALUES ($1, $2, NOW(), NOW())
      ON CONFLICT (key) DO UPDATE
        SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at
      """,
      [@cursor_key, value]
    )
  end
end
