defmodule Tuist.IngestRepo.Migrations.AddOwnHashToXcodeTargetsByProject do
  @moduledoc """
  Adds `own_hash` to `xcode_targets_by_project`: the fingerprint of a target's
  own content, hashed once when the row is written instead of from fourteen
  string columns on every read.

  The module cache analytics classify a miss by comparing this fingerprint
  with the module's previous build. Computing it per query meant reading all
  fourteen subhash columns and hashing them for every row in the window, which
  on the busiest project was 3 GiB read and 3.5 GiB of memory per query and 5
  to 12 seconds. With the fingerprint stored, the same query reads 1.2 GiB,
  peaks at 1.4 GiB and takes about 2 seconds.

  The column is `MATERIALIZED`, so rows the materialized view writes from now
  on carry it and rows written before are computed on read until the
  background mutation submitted here has rewritten them. The mutation is
  asynchronous: the deploy does not wait for it, and until it finishes the
  affected queries cost what they cost today, no more.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.Repo

  @disable_ddl_transaction true
  @disable_migration_lock true

  @table "xcode_targets_by_project"
  @column "own_hash"
  @lock_id 20_260_907_150_000

  @expression """
  cityHash64(
    sources_hash, resources_hash, copy_files_hash, core_data_models_hash,
    target_scripts_hash, environment_hash, headers_hash, deployment_target_hash,
    info_plist_hash, entitlements_hash, project_settings_hash,
    target_settings_hash, buildable_folders_hash, additional_hashing_inputs_hash
  )
  """

  def up do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Repo, fn _repo ->
        Repo.transaction(
          fn ->
            Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_id])

            IngestRepo.query!("""
            ALTER TABLE #{@table}
            ADD COLUMN IF NOT EXISTS #{@column} UInt64 MATERIALIZED #{@expression}
            """)

            if needs_materialization?() do
              IngestRepo.query!("""
              ALTER TABLE #{@table}
              MATERIALIZE COLUMN #{@column}
              SETTINGS mutations_sync = 0
              """)
            end
          end,
          timeout: :infinity
        )
      end)
  end

  def down do
    IngestRepo.query!("ALTER TABLE #{@table} DROP COLUMN IF EXISTS #{@column}")
  end

  # Every pod runs ClickHouse migrations on boot and each MATERIALIZE COLUMN
  # rewrites the column in every part again, so it is submitted only while
  # parts without the column exist and no mutation for it is pending.
  defp needs_materialization? do
    {:ok, %{rows: [[parts_without_column]]}} =
      IngestRepo.query(
        """
        SELECT count()
        FROM system.parts
        WHERE database = currentDatabase()
          AND table = {table:String}
          AND active
          AND name NOT IN (
            SELECT name
            FROM system.parts_columns
            WHERE database = currentDatabase()
              AND table = {table:String}
              AND active
              AND column = {column:String}
          )
        """,
        %{table: @table, column: @column}
      )

    {:ok, %{rows: [[pending_mutations]]}} =
      IngestRepo.query(
        """
        SELECT count()
        FROM system.mutations
        WHERE database = currentDatabase()
          AND table = {table:String}
          AND is_done = 0
          AND command LIKE {command:String}
        """,
        %{table: @table, command: "%MATERIALIZE COLUMN #{@column}%"}
      )

    parts_without_column > 0 and pending_mutations == 0
  end
end
