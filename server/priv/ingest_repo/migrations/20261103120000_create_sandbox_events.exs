defmodule Tuist.IngestRepo.Migrations.CreateSandboxEvents do
  @moduledoc """
  One row per sandbox lifecycle change (`created`, `started`, `paused`,
  `archived`, `failed`, `deleted`), with the sandbox's shape at the time.
  The dashboard derives counts, run sessions (`started` up to the next stop)
  and concurrency from it, since sandbox rows themselves are deleted.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS sandbox_events (
      id UUID,
      account_id Int64,
      sandbox_id UUID,
      event LowCardinality(String),
      source LowCardinality(String),
      vcpus UInt16,
      memory_mb UInt32,
      inserted_at DateTime64(6)
    ) ENGINE = #{Migration.engine("MergeTree")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (account_id, inserted_at, sandbox_id)
    TTL toDateTime(inserted_at) + INTERVAL 730 DAY
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS sandbox_events")
  end
end
