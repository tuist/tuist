defmodule Tuist.IngestRepo.Migrations.AddProjectIdToXcodeTargets do
  @moduledoc """
  Denormalizes `project_id` onto `xcode_targets` and copies the columns the
  module cache analytics read into `xcode_targets_by_project`, ordered by
  `(project_id, name, inserted_at)` and kept current by a materialized view.

  `xcode_targets` carries every project's rows and is ordered by
  `(inserted_at, id)`. The module cache analytics reach a project only through
  a join on `command_events`, which gives the scan nothing to prune with: at the
  dashboard's 30-day default a single query read ~960M rows and ~30 GiB in
  production and took ~18s, and the Modules page runs five of them at once.
  Against the new table the same queries are a primary-key range over one
  project's rows.

  A projection on `xcode_targets` would need the new column backfilled with a
  mutation, and the table's `proj_by_command_event` projection is a `SELECT *`
  copy of every column, so ClickHouse would rebuild that copy for each mutated
  part: the whole table read and written again. Copying into a table of its
  own reads each partition once, writes about a third of the table's size, and
  never rewrites `xcode_targets`. Same shape as `test_case_runs_by_project`.

  The backfill runs partition by partition before the view exists, so a retry
  can drop and redo a partition without racing the view. The view is created
  once every partition is copied, and a final pass copies the rows that landed
  between a partition's copy and the view's creation. Serialized across pods
  with a Postgres advisory lock the way
  `20260721115000_add_project_id_to_test_case_events` is: ClickHouse migrations
  run without a migration lock, and one pod dropping the dictionary while
  another is mid-copy would crash that pod on boot.
  """
  use Ecto.Migration

  alias Tuist.ClickHouseDictionarySource
  alias Tuist.IngestRepo
  alias Tuist.Repo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @table "xcode_targets_by_project"
  @view "xcode_targets_by_project_mv"
  @dict_name "command_event_project_ids_for_xcode_targets"
  @lock_id 20_260_905_120_000

  # Rows written before this migration deployed carry project_id 0 and are
  # resolved through the dictionary.
  @project_id_expr "if(project_id = 0, dictGetOrDefault('#{@dict_name}', 'project_id', command_event_id, toInt64(0)), project_id)"

  # A row's inserted_at is stamped when it enters the ingestion buffer, up to
  # flush_interval_ms (5s in production) before it lands in ClickHouse. The gap
  # pass reaches this far back before the copy started so buffered rows are
  # covered even when a flush was deferred.
  @buffer_margin_seconds 300
  @settle_ms 15_000

  @columns ~w(
    project_id inserted_at command_event_id name product binary_cache_hash binary_cache_hit
    sources_hash resources_hash copy_files_hash core_data_models_hash target_scripts_hash
    environment_hash headers_hash deployment_target_hash info_plist_hash entitlements_hash
    dependencies_hash project_settings_hash target_settings_hash buildable_folders_hash
    additional_hashing_inputs_hash external_hash dependencies
  )

  def up do
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Repo, fn _repo ->
        Repo.transaction(
          fn ->
            Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_id])

            add_project_id_column()
            create_table()

            try do
              create_project_ids_dictionary()

              if view_exists?() do
                fill_gap()
              else
                backfilled? = backfill_by_partition()
                create_view()
                if backfilled?, do: Process.sleep(@settle_ms)
                fill_gap()
              end
            after
              IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")
            end
          end,
          timeout: :infinity
        )
      end)
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS #{@view}")
    IngestRepo.query!("DROP TABLE IF EXISTS #{@table}")
    IngestRepo.query!("ALTER TABLE xcode_targets DROP COLUMN IF EXISTS project_id")
  end

  defp add_project_id_column do
    IngestRepo.query!("""
    ALTER TABLE xcode_targets
    ADD COLUMN IF NOT EXISTS project_id Int64 DEFAULT 0 AFTER command_event_id
    """)
  end

  defp create_table do
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS #{@table} (
      project_id Int64,
      inserted_at DateTime,
      command_event_id UUID,
      name String,
      product LowCardinality(String) DEFAULT '',
      binary_cache_hash Nullable(String),
      binary_cache_hit Enum8('miss' = 0, 'local' = 1, 'remote' = 2),
      sources_hash String DEFAULT '',
      resources_hash String DEFAULT '',
      copy_files_hash String DEFAULT '',
      core_data_models_hash String DEFAULT '',
      target_scripts_hash String DEFAULT '',
      environment_hash String DEFAULT '',
      headers_hash String DEFAULT '',
      deployment_target_hash String DEFAULT '',
      info_plist_hash String DEFAULT '',
      entitlements_hash String DEFAULT '',
      dependencies_hash String DEFAULT '',
      project_settings_hash String DEFAULT '',
      target_settings_hash String DEFAULT '',
      buildable_folders_hash String DEFAULT '',
      additional_hashing_inputs_hash String DEFAULT '',
      external_hash String DEFAULT '',
      dependencies Array(String) DEFAULT []
    ) ENGINE = MergeTree
    PARTITION BY toYYYYMMDD(inserted_at)
    ORDER BY (project_id, name, inserted_at)
    TTL inserted_at + INTERVAL 30 DAY
    """)
  end

  defp create_view do
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS #{@view}
    TO #{@table}
    AS SELECT #{Enum.join(@columns, ", ")}
    FROM xcode_targets
    WHERE project_id != 0
    """)
  end

  defp create_project_ids_dictionary do
    IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")

    IngestRepo.query!(
      """
      CREATE DICTIONARY #{@dict_name} (
        id UUID,
        project_id Int64
      )
      PRIMARY KEY id
      SOURCE(#{ClickHouseDictionarySource.local_query(IngestRepo, dict_source_query())})
      LAYOUT(HASHED())
      LIFETIME(0)
      """,
      [],
      ClickHouseDictionarySource.query_opts()
    )
  end

  # command_events holds ~34M rows, but xcode_targets keeps 30 days and a
  # target row is written after its event, so only events from the last few
  # weeks can be referenced. The dictionary is built from those alone.
  defp dict_source_query do
    database = Keyword.fetch!(IngestRepo.config(), :database)

    "SELECT id, project_id FROM #{database}.command_events WHERE created_at >= now() - INTERVAL 35 DAY"
  end

  defp backfill_by_partition do
    {:ok, %{rows: partitions}} =
      IngestRepo.query("""
      SELECT DISTINCT partition
      FROM system.parts
      WHERE database = currentDatabase() AND table = 'xcode_targets' AND active
      ORDER BY partition
      """)

    for [partition] <- partitions do
      partition = String.to_integer(partition)
      Logger.info("Copying xcode_targets partition #{partition} into #{@table}")

      IngestRepo.query!("ALTER TABLE #{@table} DROP PARTITION #{partition}")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          """
          INSERT INTO #{@table} (#{Enum.join(@columns, ", ")})
          SELECT #{select_list()}
          FROM xcode_targets
          WHERE toYYYYMMDD(inserted_at) = {partition:UInt32} AND #{@project_id_expr} != 0
          """,
          %{partition: partition},
          timeout: 1_200_000
        )
      end)
    end

    partitions != []
  end

  # Rows that landed in xcode_targets after their partition was copied and
  # before the view existed are in neither copy. The window is bounded by the
  # table's and the view's creation, so a retry covers the same rows.
  defp fill_gap do
    gap_start = NaiveDateTime.add(created_at(@table), -@buffer_margin_seconds, :second)
    gap_end = created_at(@view)

    Logger.info("Copying xcode_targets rows between #{gap_start} and #{gap_end} into #{@table}")

    retry_on_shutting_down(fn ->
      IngestRepo.query!(
        """
        INSERT INTO #{@table} (#{Enum.join(@columns, ", ")})
        SELECT #{select_list()}
        FROM xcode_targets
        WHERE inserted_at >= {gap_start:DateTime}
          AND inserted_at < {gap_end:DateTime}
          AND #{@project_id_expr} != 0
          AND (command_event_id, name) NOT IN (
            SELECT command_event_id, name
            FROM #{@table}
            WHERE inserted_at >= {gap_start:DateTime} AND inserted_at < {gap_end:DateTime}
          )
        """,
        %{gap_start: gap_start, gap_end: gap_end},
        timeout: 1_200_000
      )
    end)
  end

  defp select_list do
    Enum.map_join(@columns, ", ", fn
      "project_id" -> @project_id_expr
      column -> column
    end)
  end

  defp view_exists? do
    {:ok, %{rows: [[count]]}} =
      IngestRepo.query(
        "SELECT count() FROM system.tables WHERE database = currentDatabase() AND name = {name:String}",
        %{name: @view}
      )

    count > 0
  end

  defp created_at(name) do
    {:ok, %{rows: [[created_at]]}} =
      IngestRepo.query(
        "SELECT metadata_modification_time FROM system.tables WHERE database = currentDatabase() AND name = {name:String}",
        %{name: name}
      )

    created_at
  end

  defp retry_on_shutting_down(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      if attempts > 1 and String.contains?(to_string(e.message), "TABLE_IS_READ_ONLY") do
        Logger.warning("Table is shutting down, retrying in 5s (#{attempts - 1} attempts left)")
        Process.sleep(:timer.seconds(5))
        retry_on_shutting_down(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
