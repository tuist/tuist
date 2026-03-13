defmodule Tuist.IngestRepo.Migrations.CreateShardSessions do
  @moduledoc """
  Creates the shard_sessions table in ClickHouse.

  Stores metadata about test sharding sessions including shard assignments
  and the associated test bundle. Uses ReplacingMergeTree so we can "update"
  rows (e.g., marking upload_completed) by inserting a newer version.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    CREATE TABLE IF NOT EXISTS shard_sessions
    (
      `id` UUID,
      `session_id` String,
      `project_id` Int64,
      `shard_count` Int32,
      `granularity` LowCardinality(String) DEFAULT 'module',
      `shard_assignments` String DEFAULT '[]',
      `upload_completed` UInt8 DEFAULT 0,
      `bundle_object_key` String DEFAULT '',
      `xctestrun_object_key` String DEFAULT '',
      `inserted_at` DateTime64(6)
    )
    ENGINE = ReplacingMergeTree(inserted_at)
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, session_id)
    SETTINGS index_granularity = 8192
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DROP TABLE IF EXISTS shard_sessions")
  end
end
