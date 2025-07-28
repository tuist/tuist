defmodule Tuist.ClickHouseRepo.Migrations.AddCommandEventIDtoXcode do
  use Ecto.Migration

  def up do
    execute("""
      CREATE TABLE xcode_projects_new (
        id String,
        name String,
        path String,
        xcode_graph_id UUID,
        command_event_id UUID,
        inserted_at DateTime
      )
      ENGINE = MergeTree()
      PARTITION BY toYYYYMMDD(inserted_at)
      ORDER BY (inserted_at, id)
    """)

    execute("RENAME TABLE xcode_projects TO xcode_projects_backup")

    execute("""
      INSERT INTO xcode_projects_new
      SELECT
        xp.id AS id,
        xp.name AS name,
        xp.path AS path,
        xp.xcode_graph_id AS xcode_graph_id,
        xg.command_event_id AS command_event_id,
        xp.inserted_at AS inserted_at
      FROM xcode_projects_backup xp
      LEFT JOIN xcode_graphs xg ON xp.xcode_graph_id = xg.id
    """)

    execute("RENAME TABLE xcode_projects_new TO xcode_projects")

    execute("""
      CREATE TABLE xcode_targets_new (
        id String,
        name String,
        binary_cache_hash Nullable(String),
        binary_cache_hit Enum8('miss' = 0, 'local' = 1, 'remote' = 2),
        binary_build_duration Nullable(UInt32),
        selective_testing_hash Nullable(String),
        selective_testing_hit Enum8('miss' = 0, 'local' = 1, 'remote' = 2),
        xcode_project_id UUID,
        command_event_id UUID,
        inserted_at DateTime
      )
      ENGINE = MergeTree()
      PARTITION BY toYYYYMMDD(inserted_at)
      ORDER BY (inserted_at, id)
    """)

    execute("RENAME TABLE xcode_targets TO xcode_targets_backup")

    execute("""
      INSERT INTO xcode_targets_new
      SELECT
        xt.id AS id,
        xt.name AS name,
        xt.binary_cache_hash AS binary_cache_hash,
        xt.binary_cache_hit AS binary_cache_hit,
        xt.binary_build_duration AS binary_build_duration,
        xt.selective_testing_hash AS selective_testing_hash,
        xt.selective_testing_hit AS selective_testing_hit,
        xt.xcode_project_id AS xcode_project_id,
        xg.command_event_id AS command_event_id,
        xt.inserted_at AS inserted_at
      FROM xcode_targets_backup xt
      LEFT JOIN xcode_projects_backup xp ON xt.xcode_project_id = xp.id
      LEFT JOIN xcode_graphs xg ON xp.xcode_graph_id = xg.id
    """)

    execute("RENAME TABLE xcode_targets_new TO xcode_targets")

    execute(
      "ALTER TABLE xcode_targets ADD INDEX command_event_id_idx (command_event_id) TYPE bloom_filter GRANULARITY 4"
    )

    execute(
      "ALTER TABLE xcode_targets ADD INDEX name_text_search_idx (name) TYPE ngrambf_v1(4, 65536, 3, 0) GRANULARITY 4"
    )

    execute("DROP VIEW xcode_targets_denormalized")
  end

  def down do
    execute("DROP TABLE xcode_projects")
    execute("DROP TABLE xcode_targets")
    execute("RENAME TABLE xcode_projects_backup TO xcode_projects")
    execute("RENAME TABLE xcode_targets_backup TO xcode_targets")
  end
end
