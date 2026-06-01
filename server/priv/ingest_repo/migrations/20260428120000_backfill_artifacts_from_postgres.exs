defmodule Tuist.IngestRepo.Migrations.BackfillArtifactsFromPostgres do
  @moduledoc """
  Phase 2 of the PG → CH `artifacts` migration started in #10493.
  Drains every bundle whose dual-write didn't replicate its artifacts
  (`artifacts_replicated_to_ch = false`) into ClickHouse, batching by
  bundle and flipping the flag once each batch's CH insert returns.

  The flag doubles as the resume cursor — a killed run restarts and
  the WHERE filter naturally skips bundles whose flag was already
  flipped. The candidate set is exactly two populations:

    1. Pre-phase-1 history: rows that existed before the column was
       added and were column-defaulted to `false` by the schema migration.
    2. Bundles whose live dual-write raised — see the rescue clause in
       `Tuist.Bundles.replicate_artifacts_to_clickhouse/2`, which flips
       the flag from its insert-time default of `true` back to `false`.

  Bundles whose dual-write is *in flight* never enter the scan because
  they are inserted with `artifacts_replicated_to_ch = true` from the
  start (see `Tuist.Bundles.Bundle`). The migration cannot race with a
  live dual-write.

  Live schemas (`Bundle`, `Artifact`, `ArtifactIngest`) are deliberately
  not referenced from this migration. Migrations are immutable history,
  but self-hosted upgrades may run them long after the schemas have
  drifted from the table layout the migration assumed — referencing a
  live module here would silently rewrite the meaning of this step.
  Raw `from(... in "table", ...)` pins the migration to the column
  shape that existed at the time it was written.
  """

  use Ecto.Migration

  import Ecto.Query

  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Bundle batch sizes the resume cursor (the `artifacts_replicated_to_ch`
  # flag is flipped per-batch). Artifact streaming below decouples peak
  # BEAM memory from the batch's total artifact count, so the bundle
  # batch can stay large enough to keep wall time inside the deploy
  # hook's 60-minute window without risking OOM on a tail batch.
  @bundle_batch_size 100
  # Caps the artifact list (and its CH-encoded copy) the migration holds
  # at any moment. A 1000-bundle batch with a heavy tail spiked BEAM
  # memory past 8 GB and OOM-evicted the migration pod in production;
  # streaming through 5K-row chunks keeps peak working set in the tens
  # of MB regardless of how heavy a bundle batch turns out to be.
  @artifact_chunk_size 5_000
  # Matches the throttle other long-running CH backfills use
  # (`BackfillTestRunsFromCommandEvents`, `BackfillFirstRunEvents`):
  # gives live PG/CH traffic breathing room and lets CH merges keep up
  # so we don't trip `parts_to_throw_insert`.
  @throttle_ms 500

  @ch_types %{
    id: :uuid,
    bundle_id: :uuid,
    artifact_type: "LowCardinality(String)",
    path: :string,
    size: :i64,
    shasum: :string,
    artifact_id: {:nullable, :uuid},
    inserted_at: "DateTime64(6)",
    updated_at: "DateTime64(6)"
  }

  def up do
    # The PostgreSQL repo is not started during ClickHouse migrations.
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Logger.info("Starting artifact backfill to ClickHouse")
    drain(0, 0)
  end

  def down, do: :ok

  defp drain(bundle_total, artifact_total) do
    case run_batch() do
      :done ->
        Logger.info(
          "Artifact backfill complete: #{bundle_total} bundles, #{artifact_total} artifacts replicated"
        )

      {bundles_count, artifacts_count} ->
        new_bundle_total = bundle_total + bundles_count
        new_artifact_total = artifact_total + artifacts_count

        Logger.info(
          "Backfilled batch: #{bundles_count} bundles / #{artifacts_count} artifacts " <>
            "(running total: #{new_bundle_total} bundles / #{new_artifact_total} artifacts)"
        )

        Process.sleep(@throttle_ms)
        drain(new_bundle_total, new_artifact_total)
    end
  end

  defp run_batch do
    case fetch_unreplicated_bundle_ids() do
      [] ->
        :done

      bundle_ids ->
        artifacts_count = stream_and_insert_artifacts(bundle_ids)
        mark_replicated(bundle_ids)
        {length(bundle_ids), artifacts_count}
    end
  end

  defp fetch_unreplicated_bundle_ids do
    from(b in "bundles",
      where: b.artifacts_replicated_to_ch == false,
      order_by: [asc: b.id],
      limit: ^@bundle_batch_size,
      select: b.id
    )
    |> Repo.all(timeout: :infinity)
  end

  # Streams the bundle batch's artifacts from Postgres in chunks of
  # `@artifact_chunk_size`, encoding and inserting each chunk into
  # ClickHouse before reading the next. Postgres opens a server-side
  # cursor for the duration of the surrounding transaction, so the
  # BEAM never holds more than one chunk at once even when the batch
  # spans bundles with tens of thousands of artifacts each.
  defp stream_and_insert_artifacts(bundle_ids) do
    query =
      from(a in "artifacts",
        where: a.bundle_id in ^bundle_ids,
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

    {:ok, count} =
      Repo.transaction(
        fn ->
          query
          |> Repo.stream(max_rows: @artifact_chunk_size)
          |> Stream.chunk_every(@artifact_chunk_size)
          |> Enum.reduce(0, fn chunk, acc ->
            encoded = Enum.map(chunk, &encode_for_ch/1)

            IngestRepo.insert_all("artifacts", encoded,
              types: @ch_types,
              timeout: :infinity,
              log: false
            )

            # Force a GC between chunks so the encoded list and the raw
            # row chunk are reclaimed before the cursor pulls the next
            # page, instead of accumulating across iterations.
            :erlang.garbage_collect()
            acc + length(encoded)
          end)
        end,
        timeout: :infinity
      )

    count
  end

  defp mark_replicated(bundle_ids) do
    Repo.update_all(
      from(b in "bundles", where: b.id in ^bundle_ids),
      [set: [artifacts_replicated_to_ch: true]],
      timeout: :infinity,
      log: false
    )
  end

  # PG returns UUIDs as 16-byte binaries (raw column, no schema cast)
  # and timestamps as `DateTime` at second precision. CH expects
  # 36-char UUID strings and `NaiveDateTime` at microsecond precision
  # for the `DateTime64(6)` columns.
  defp encode_for_ch(row) do
    %{
      row
      | id: Ecto.UUID.load!(row.id),
        bundle_id: Ecto.UUID.load!(row.bundle_id),
        artifact_id: row.artifact_id && Ecto.UUID.load!(row.artifact_id),
        inserted_at: to_naive_usec(row.inserted_at),
        updated_at: to_naive_usec(row.updated_at)
    }
  end

  defp to_naive_usec(%DateTime{} = dt) do
    dt |> DateTime.to_naive() |> bump_usec_precision()
  end

  defp to_naive_usec(%NaiveDateTime{} = ndt), do: bump_usec_precision(ndt)

  defp bump_usec_precision(%NaiveDateTime{microsecond: {value, _}} = ndt) do
    %{ndt | microsecond: {value, 6}}
  end
end
