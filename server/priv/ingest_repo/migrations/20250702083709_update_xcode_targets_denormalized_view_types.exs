defmodule Tuist.ClickHouseRepo.Migrations.UpdateXcodeTargetsDenormalizedViewTypes do
  use Ecto.Migration

  def up do
    # Drop the existing materialized view
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS xcode_targets_denormalized"

    # Recreate the materialized view with updated types
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW xcode_targets_denormalized
    ENGINE = MergeTree()
    ORDER BY (command_event_id, xcode_project_id, inserted_at)
    AS
    SELECT
      xt.id as id,
      xt.name as name,
      xt.binary_cache_hash as binary_cache_hash,
      xt.binary_cache_hit as binary_cache_hit,
      xt.binary_build_duration as binary_build_duration,
      xt.selective_testing_hash as selective_testing_hash,
      xt.selective_testing_hit as selective_testing_hit,
      xt.xcode_project_id as xcode_project_id,
      xt.inserted_at as inserted_at,
      xp.name as project_name,
      xp.path as project_path,
      xp.xcode_graph_id as xcode_graph_id,
      xg.name as graph_name,
      xg.command_event_id as command_event_id,
      xg.binary_build_duration as graph_binary_build_duration
    FROM xcode_targets xt
    INNER JOIN xcode_projects xp ON xt.xcode_project_id = xp.id
    INNER JOIN xcode_graphs xg ON xp.xcode_graph_id = xg.id
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS xcode_targets_denormalized"
  end
end
