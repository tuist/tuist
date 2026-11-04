defmodule Tuist.IngestRepo.Migrations.CreateSandboxEvents do
  @moduledoc """
  One row per sandbox lifecycle change (`created`, `started`, `paused`,
  `archived`, `failed`, `deleted`), with the sandbox's shape at the time,
  plus a `setup` row when an Amp Orb's `.agents/setup` is seen to finish.
  A `started` row of a boot carries what it booted from (`boot_source`) and
  how long the boot took (`duration_ms`); a `setup` row carries how long
  setup ran.
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
      boot_source LowCardinality(String) DEFAULT '',
      duration_ms UInt32 DEFAULT 0,
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
