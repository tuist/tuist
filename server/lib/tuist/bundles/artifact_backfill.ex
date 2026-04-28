defmodule Tuist.Bundles.ArtifactBackfill do
  @moduledoc """
  Backfills the ClickHouse `artifacts` table from PostgreSQL.

  Iterates over `bundles` rows where `artifacts_replicated_to_ch = false`
  and replicates each batch's artifacts to ClickHouse via `ArtifactIngest`,
  then flips the bundle flag in PostgreSQL. Once the loop drains, every
  bundle's artifacts are present in ClickHouse and the live dual-write
  path in `Tuist.Bundles.create_bundle/2` keeps them in sync from there.

  The `artifacts_replicated_to_ch` flag doubles as the resume cursor: a
  killed run restarts and the WHERE filter naturally skips bundles whose
  flag was already flipped on the previous run.

  Race window: between the ClickHouse insert and the PostgreSQL flag
  update for a given batch. A crash inside that window will, on retry,
  re-insert that batch's rows. The destination is `MergeTree` (no
  row-level deduplication), so the duplicates persist until something
  else collapses them — but the volume is bounded by one
  `@bundle_batch_size`-batch and a crash, which we accept rather than
  pay the cost of a deduplicating engine or per-batch CH existence
  checks.

  Designed to be callable both from the long-running phase 2 migration
  and ad-hoc from `iex` for live recovery if the dual-write falls behind
  for any reason post-cutover.
  """

  import Ecto.Query

  alias Tuist.Bundles.Artifact
  alias Tuist.Bundles.ArtifactIngest
  alias Tuist.Bundles.Bundle
  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  @bundle_batch_size 100

  @doc """
  Drains every unreplicated bundle in batches of `#{@bundle_batch_size}`.
  Returns `{bundle_total, artifact_total}`.
  """
  def run do
    Logger.info("Starting artifact backfill to ClickHouse")
    drain(0, 0)
  end

  @doc """
  Replicates a single batch. Returns `:done` when no unreplicated bundles
  remain, or `{:ok, %{bundles: n, artifacts: m}}` after replicating one
  batch.
  """
  def run_batch do
    case fetch_unreplicated_bundle_ids() do
      [] ->
        :done

      bundle_ids ->
        artifacts = fetch_artifacts(bundle_ids)
        if artifacts != [], do: IngestRepo.insert_all(ArtifactIngest, artifacts)
        mark_replicated(bundle_ids)
        {:ok, %{bundles: length(bundle_ids), artifacts: length(artifacts)}}
    end
  end

  defp drain(bundle_total, artifact_total) do
    case run_batch() do
      :done ->
        Logger.info("Artifact backfill complete: #{bundle_total} bundles, #{artifact_total} artifacts replicated")

        {bundle_total, artifact_total}

      {:ok, %{bundles: bundle_count, artifacts: artifact_count}} ->
        new_bundle_total = bundle_total + bundle_count
        new_artifact_total = artifact_total + artifact_count

        Logger.info(
          "Backfilled batch: #{bundle_count} bundles / #{artifact_count} artifacts " <>
            "(running total: #{new_bundle_total} bundles / #{new_artifact_total} artifacts)"
        )

        drain(new_bundle_total, new_artifact_total)
    end
  end

  defp fetch_unreplicated_bundle_ids do
    Repo.all(
      from(b in Bundle,
        where: b.artifacts_replicated_to_ch == false,
        order_by: [asc: b.id],
        limit: ^@bundle_batch_size,
        select: b.id
      ),
      timeout: :infinity
    )
  end

  defp fetch_artifacts(bundle_ids) do
    from(a in Artifact,
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
    |> Repo.all(timeout: :infinity)
    |> Enum.map(&ArtifactIngest.from_pg/1)
  end

  defp mark_replicated(bundle_ids) do
    Repo.update_all(
      from(b in Bundle, where: b.id in ^bundle_ids),
      set: [artifacts_replicated_to_ch: true]
    )
  end
end
