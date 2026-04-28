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

  # Sized so each batch lands ~100K-200K artifacts in CH (the band
  # CH ingests most happily) while keeping BEAM memory under ~200MB
  # even on a tail bundle with hundreds of artifacts. With ~225M
  # artifacts on production this works out to a few hundred batches,
  # so the inter-batch throttle below stays a small slice of total
  # runtime instead of dominating it.
  @bundle_batch_size 1_000
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
        artifacts = fetch_artifacts(bundle_ids)

        if artifacts != [] do
          IngestRepo.insert_all("artifacts", artifacts,
            types: @ch_types,
            timeout: :infinity,
            log: false
          )
        end

        mark_replicated(bundle_ids)
        {length(bundle_ids), length(artifacts)}
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

  defp fetch_artifacts(bundle_ids) do
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
    |> Repo.all(timeout: :infinity, log: false)
    |> Enum.map(&encode_for_ch/1)
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
