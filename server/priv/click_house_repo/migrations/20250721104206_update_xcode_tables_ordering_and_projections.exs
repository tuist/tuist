defmodule Tuist.ClickHouseRepo.Migrations.UpdateXcodeTablesOrderingAndProjections do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE TABLE xcode_graphs_new (
      id String,
      name String,
      command_event_id UUID,
      binary_build_duration Nullable(UInt32),
      inserted_at DateTime
    ) ENGINE = MergeTree()
    PARTITION BY toYYYYMMDD(inserted_at)
    ORDER BY (inserted_at, id)
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "INSERT INTO xcode_graphs_new SELECT id, name, command_event_id, binary_build_duration, inserted_at FROM xcode_graphs"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_graphs TO xcode_graphs_bak"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_graphs_new TO xcode_graphs"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE TABLE xcode_projects_new (
      id String,
      name String,
      path String,
      xcode_graph_id String,
      inserted_at DateTime
    ) ENGINE = MergeTree()
    PARTITION BY toYYYYMMDD(inserted_at)
    ORDER BY (inserted_at, id)
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "INSERT INTO xcode_projects_new SELECT id, name, path, xcode_graph_id, inserted_at FROM xcode_projects"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_projects TO xcode_projects_bak"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_projects_new TO xcode_projects"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE TABLE xcode_targets_new (
      id String,
      name String,
      binary_cache_hash Nullable(String),
      binary_cache_hit Enum8('miss' = 0, 'local' = 1, 'remote' = 2),
      binary_build_duration Nullable(UInt32),
      selective_testing_hash Nullable(String),
      selective_testing_hit Enum8('miss' = 0, 'local' = 1, 'remote' = 2),
      xcode_project_id String,
      inserted_at DateTime
    ) ENGINE = MergeTree()
    PARTITION BY toYYYYMMDD(inserted_at)
    ORDER BY (inserted_at, id)
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "INSERT INTO xcode_targets_new SELECT id, name, binary_cache_hash, binary_cache_hit, binary_build_duration, selective_testing_hash, selective_testing_hit, xcode_project_id, inserted_at FROM xcode_targets"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_targets TO xcode_targets_bak"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_targets_new TO xcode_targets"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_projects
    ADD PROJECTION proj_by_graph_id (
      SELECT
        id,
        name,
        path,
        xcode_graph_id,
        inserted_at
      ORDER BY xcode_graph_id, inserted_at, id
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_projects MATERIALIZE PROJECTION proj_by_graph_id"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_targets
    ADD PROJECTION proj_by_project_id (
      SELECT
        id,
        name,
        binary_cache_hash,
        binary_cache_hit,
        binary_build_duration,
        selective_testing_hash,
        selective_testing_hit,
        xcode_project_id,
        inserted_at
      ORDER BY xcode_project_id, inserted_at, id
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets MATERIALIZE PROJECTION proj_by_project_id"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS xcode_targets_denormalized"

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
    FROM xcode_targets AS xt
    INNER JOIN (SELECT * FROM xcode_projects WHERE inserted_at >= (now() - toIntervalMinute(10))) AS xp ON xt.xcode_project_id = xp.id
    INNER JOIN (SELECT * FROM xcode_graphs WHERE inserted_at >= (now() - toIntervalMinute(10))) AS xg ON xp.xcode_graph_id = xg.id
    SETTINGS join_algorithm = 'partial_merge'
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS xcode_targets_denormalized"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets DROP PROJECTION IF EXISTS proj_by_project_id"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_projects DROP PROJECTION IF EXISTS proj_by_graph_id"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_targets TO xcode_targets_new"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_targets_bak TO xcode_targets"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP TABLE IF EXISTS xcode_targets_new"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_projects TO xcode_projects_new"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_projects_bak TO xcode_projects"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP TABLE IF EXISTS xcode_projects_new"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_graphs TO xcode_graphs_new"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "RENAME TABLE xcode_graphs_bak TO xcode_graphs"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP TABLE IF EXISTS xcode_graphs_new"

    # Recreate the previous version of the materialized view
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
end
