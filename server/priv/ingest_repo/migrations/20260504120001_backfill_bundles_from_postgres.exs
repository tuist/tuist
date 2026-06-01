defmodule Tuist.IngestRepo.Migrations.BackfillBundlesFromPostgres do
  @moduledoc """
  Drains every bundle whose dual-write didn't replicate the row to
  ClickHouse (`replicated_to_ch = false`) into the CH `bundles` table,
  batching by bundle and flipping the flag once each batch's CH insert
  returns.

  The flag doubles as the resume cursor — a killed run restarts and
  the WHERE filter naturally skips bundles whose flag was already
  flipped. The candidate set is exactly two populations:

    1. Pre-dual-write history: rows that existed before the column
       was added and were column-defaulted to `false` by the schema
       migration.
    2. Bundles whose live dual-write raised — see the rescue clause
       in `Tuist.Bundles.replicate_bundle_to_clickhouse/1`, which
       flips the flag from its insert-time default of `true` back to
       `false`.

  Bundles whose dual-write is *in flight* never enter the scan
  because they are inserted with `replicated_to_ch = true` from the
  start (see `Tuist.Bundles.Bundle`). The migration cannot race with
  a live dual-write.

  Live schemas (`Bundle`, `BundleIngest`) are deliberately not
  referenced from this migration. Migrations are immutable history,
  but self-hosted upgrades may run them long after the schemas have
  drifted from the table layout the migration assumed — referencing
  a live module here would silently rewrite the meaning of this
  step. Raw `from(... in "bundles", ...)` and inline enum mappings
  pin the migration to the column shape that existed when it was
  written.
  """

  use Ecto.Migration

  import Ecto.Query

  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @batch_size 500
  @throttle_ms 500

  @ch_types %{
    id: :uuid,
    app_bundle_id: :string,
    name: :string,
    install_size: :i64,
    download_size: {:nullable, :i64},
    git_branch: {:nullable, :string},
    git_commit_sha: {:nullable, :string},
    git_ref: {:nullable, :string},
    supported_platforms: "Array(LowCardinality(String))",
    version: :string,
    type: "LowCardinality(String)",
    project_id: :i64,
    uploaded_by_account_id: {:nullable, :i64},
    inserted_at: "DateTime64(6)",
    updated_at: "DateTime64(6)"
  }

  # Frozen at the time of writing — kept out of the live `Tuist.Bundles.Bundle`
  # schema deliberately so a future enum reordering doesn't silently rewrite
  # the meaning of historic backfilled rows.
  @platform_by_int %{
    0 => "ios",
    1 => "ios_simulator",
    2 => "tvos",
    3 => "tvos_simulator",
    4 => "watchos",
    5 => "watchos_simulator",
    6 => "visionos",
    7 => "visionos_simulator",
    8 => "macos",
    9 => "android"
  }

  @type_by_int %{
    0 => "ipa",
    1 => "app",
    2 => "xcarchive",
    3 => "aab",
    4 => "apk"
  }

  def up do
    # The PostgreSQL repo is not started during ClickHouse migrations.
    case Repo.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Logger.info("Starting bundle backfill to ClickHouse")
    drain(0)
  end

  def down, do: :ok

  defp drain(total) do
    case run_batch() do
      :done ->
        Logger.info("Bundle backfill complete: #{total} bundles replicated")

      count ->
        new_total = total + count
        Logger.info("Backfilled batch: #{count} bundles (running total: #{new_total})")
        Process.sleep(@throttle_ms)
        drain(new_total)
    end
  end

  defp run_batch do
    case fetch_unreplicated_bundles() do
      [] ->
        :done

      rows ->
        encoded = Enum.map(rows, &encode_for_ch/1)

        IngestRepo.insert_all("bundles", encoded,
          types: @ch_types,
          timeout: :infinity,
          log: false
        )

        mark_replicated(Enum.map(rows, & &1.id))
        length(rows)
    end
  end

  defp fetch_unreplicated_bundles do
    from(b in "bundles",
      where: b.replicated_to_ch == false,
      order_by: [asc: b.id],
      limit: ^@batch_size,
      select: %{
        id: b.id,
        app_bundle_id: b.app_bundle_id,
        name: b.name,
        install_size: b.install_size,
        download_size: b.download_size,
        git_branch: b.git_branch,
        git_commit_sha: b.git_commit_sha,
        git_ref: b.git_ref,
        supported_platforms: b.supported_platforms,
        version: b.version,
        type: b.type,
        project_id: b.project_id,
        uploaded_by_account_id: b.uploaded_by_account_id,
        inserted_at: b.inserted_at,
        updated_at: b.updated_at
      }
    )
    |> Repo.all(timeout: :infinity, log: false)
  end

  defp mark_replicated(ids) do
    Repo.update_all(
      from(b in "bundles", where: b.id in ^ids),
      [set: [replicated_to_ch: true]],
      timeout: :infinity,
      log: false
    )
  end

  defp encode_for_ch(row) do
    %{
      row
      | id: Ecto.UUID.load!(row.id),
        supported_platforms:
          Enum.map(row.supported_platforms || [], &Map.fetch!(@platform_by_int, &1)),
        type: Map.fetch!(@type_by_int, row.type),
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
