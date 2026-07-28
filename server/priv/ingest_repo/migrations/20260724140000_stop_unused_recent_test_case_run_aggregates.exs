defmodule Tuist.IngestRepo.Migrations.StopUnusedRecentTestCaseRunAggregates do
  @moduledoc """
  Stops writes and background merges for rolling test-run aggregates that the
  application no longer reads.

  The unpartitioned aggregate tables retain large arrays per test case. Merging
  the 750-run table recently exhausted the production ClickHouse memory limit
  even though the compressed source parts were small. Dropping the incremental
  materialized views stops new parts from reaching the unused tables. Setting
  the maximum automatic merge size to one byte prevents the retained parts from
  scheduling another background merge while they remain available for
  comparison during the replacement rollout.

  The 100-run table and its two materialized views stay active because rolling
  triggers are constrained to windows that it can serve.

  Production uses ClickHouse Cloud's shared table metadata. Its in-memory
  system tables remain replica-local, so merge and schema guards query every
  replica through the service's `default` cluster. Embedded development
  deployments have no cluster definition and use their local system tables.
  """

  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true
  @automatic_merge_setting "max_bytes_to_merge_at_max_space_in_pool"
  @cloud_cluster "default"

  @active_materialized_views [
    "test_case_runs_recent_100_per_case_mv",
    "test_case_runs_recent_100_success_per_case_mv"
  ]

  @retired_tables [
    "test_case_runs_recent_250_per_case",
    "test_case_runs_recent_500_per_case",
    "test_case_runs_recent_750_per_case",
    "test_case_runs_recent_per_case"
  ]

  @retired_materialized_views [
    "test_case_runs_recent_250_per_case_mv",
    "test_case_runs_recent_250_success_per_case_mv",
    "test_case_runs_recent_500_per_case_mv",
    "test_case_runs_recent_500_success_per_case_mv",
    "test_case_runs_recent_750_per_case_mv",
    "test_case_runs_recent_750_success_per_case_mv",
    "test_case_runs_recent_per_case_mv",
    "test_case_runs_recent_success_per_case_mv"
  ]

  def up do
    database = current_database!()
    cluster_available? = cloud_cluster_available?()
    replicas = replica_names!(cluster_available?)
    assert_views_present!(@active_materialized_views, database, cluster_available?, replicas)

    automatic_merge_settings!(@retired_tables, database, cluster_available?, replicas)

    # The poisoned aggregate can have a merge active almost continuously:
    # once it exceeds memory, ClickHouse retries it. Waiting for an idle
    # instant before changing the setting therefore prevents the containment
    # from ever taking effect. Stop future scheduling first. An already
    # running merge can finish or fail independently while the materialized
    # views are removed; neither operation changes the retained table's data.
    stop_automatic_merges!(@retired_tables)
    assert_automatic_merges_stopped!(@retired_tables, database, cluster_available?, replicas)
    warn_about_active_merges(@retired_tables, database, cluster_available?)

    for materialized_view <- @retired_materialized_views do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("DROP VIEW IF EXISTS #{materialized_view}")
    end

    assert_views_absent!(@retired_materialized_views, database, cluster_available?)
    assert_automatic_merges_stopped!(@retired_tables, database, cluster_available?, replicas)
  end

  def down do
    raise Ecto.MigrationError,
          "the retired materialized views require a bounded backfill before they can be re-enabled safely"
  end

  @doc false
  def automatic_merge_setting(create_table_query) do
    setting_pattern =
      ~r/(?:^|[\s,])#{@automatic_merge_setting}\s*=\s*(\d+)\b/

    case Regex.run(setting_pattern, create_table_query) do
      [_match, value] -> {:explicit, String.to_integer(value)}
      nil -> :default
    end
  end

  defp assert_views_present!(views, database, cluster_available?, replicas) do
    views
    |> table_metadata(database, cluster_available?)
    |> assert_objects_present!(
      views,
      replicas,
      "required rolling materialized views are missing on replicas"
    )
  end

  defp assert_views_absent!(views, database, cluster_available?) do
    case table_names(views, database, cluster_available?) do
      [] ->
        :ok

      present_views ->
        raise Ecto.MigrationError,
              "retired rolling materialized views remain present: #{Enum.join(present_views, ", ")}"
    end
  end

  defp warn_about_active_merges(tables, database, cluster_available?) do
    quoted_names = Enum.map_join(tables, ", ", &"'#{&1}'")
    merges_source = system_table_source("merges", cluster_available?)
    database = string_literal(database)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!("""
      SELECT DISTINCT table
      FROM #{merges_source}
      WHERE database = #{database}
        AND table IN (#{quoted_names})
      ORDER BY table
      """)

    if rows != [] do
      tables = Enum.map_join(rows, ", ", fn [table] -> table end)

      Logger.warning(
        "Retired rolling aggregates still have active background merges after automatic scheduling was stopped: #{tables}. The in-flight merges may finish or fail, but no replacement merge can be scheduled."
      )
    end
  end

  defp stop_automatic_merges!(tables) do
    for table <- tables do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("""
      ALTER TABLE #{table}
      MODIFY SETTING #{@automatic_merge_setting} = 1
      """)
    end
  end

  defp automatic_merge_settings!(tables, database, cluster_available?, replicas) do
    metadata = table_metadata(tables, database, cluster_available?)

    assert_objects_present!(
      metadata,
      tables,
      replicas,
      "required rolling aggregate tables are missing on replicas"
    )

    settings_by_table =
      Enum.group_by(
        metadata,
        fn [_replica, name, _create_table_query] -> name end,
        fn [_replica, _name, create_table_query] ->
          automatic_merge_setting(create_table_query)
        end
      )

    Enum.map(tables, fn table ->
      settings = settings_by_table |> Map.fetch!(table) |> Enum.uniq()

      case settings do
        [setting] ->
          {table, setting}

        _settings ->
          raise Ecto.MigrationError,
                "rolling aggregate table has inconsistent merge settings across replicas: #{table}"
      end
    end)
  end

  defp assert_automatic_merges_stopped!(tables, database, cluster_available?, replicas) do
    metadata = table_metadata(tables, database, cluster_available?)

    assert_objects_present!(
      metadata,
      tables,
      replicas,
      "required rolling aggregate tables are missing on replicas"
    )

    stopped_tables =
      metadata
      |> Enum.group_by(
        fn [_replica, name, _create_table_query] -> name end,
        fn [_replica, _name, create_table_query] ->
          automatic_merge_setting(create_table_query)
        end
      )
      |> Enum.filter(fn {_name, settings} ->
        Enum.all?(settings, &(&1 == {:explicit, 1}))
      end)
      |> Enum.map(fn {name, _settings} -> name end)

    mergeable_tables = tables -- stopped_tables

    if mergeable_tables != [] do
      raise Ecto.MigrationError,
            "rolling aggregate tables still allow automatic merges: #{Enum.join(mergeable_tables, ", ")}"
    end
  end

  defp table_names(names, database, cluster_available?) do
    names
    |> table_metadata(database, cluster_available?)
    |> Enum.map(fn [_replica, name, _create_table_query] -> name end)
    |> Enum.uniq()
  end

  defp assert_objects_present!(metadata, names, replicas, message) do
    present_objects =
      MapSet.new(metadata, fn [replica, name, _create_table_query] -> {replica, name} end)

    missing_objects =
      for replica <- replicas,
          name <- names,
          not MapSet.member?(present_objects, {replica, name}) do
        "#{name} on #{replica}"
      end

    if missing_objects != [] do
      raise Ecto.MigrationError, "#{message}: #{Enum.join(missing_objects, ", ")}"
    end
  end

  defp table_metadata(names, database, cluster_available?) do
    quoted_names = Enum.map_join(names, ", ", &"'#{&1}'")
    tables_source = system_table_source("tables", cluster_available?)
    database = string_literal(database)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!("""
      SELECT DISTINCT hostName() AS replica, name, create_table_query
      FROM #{tables_source}
      WHERE database = #{database}
        AND name IN (#{quoted_names})
      ORDER BY replica, name
      """)

    rows
  end

  defp replica_names!(true) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!("""
      SELECT DISTINCT hostName() AS replica
      FROM clusterAllReplicas(#{@cloud_cluster}, system.one)
      ORDER BY replica
      """)

    replica_names!(rows)
  end

  defp replica_names!(false) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} = IngestRepo.query!("SELECT hostName()")
    replica_names!(rows)
  end

  defp replica_names!([]) do
    raise Ecto.MigrationError, "ClickHouse replica discovery returned no replicas"
  end

  defp replica_names!(rows), do: Enum.map(rows, fn [replica] -> replica end)

  defp current_database! do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()")
    database
  end

  defp string_literal(value), do: "'#{String.replace(value, "'", "''")}'"

  defp cloud_cluster_available? do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!("""
      SELECT 1
      FROM system.clusters
      WHERE cluster = '#{@cloud_cluster}'
      LIMIT 1
      """)

    rows != []
  end

  defp system_table_source(table, true),
    do: "clusterAllReplicas(#{@cloud_cluster}, system.#{table})"

  defp system_table_source(table, false), do: "system.#{table}"
end
