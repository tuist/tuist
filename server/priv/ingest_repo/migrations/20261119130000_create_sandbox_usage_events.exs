defmodule Tuist.IngestRepo.Migrations.CreateSandboxUsageEvents do
  @moduledoc """
  One row per running Linux agent sandbox per node report (every 30
  seconds): the wall time since its previous report, the CPU its VM used
  in that time, its guaranteed CPU, and the CPU it is billed for, the larger
  of the guarantee over that time and the CPU used. Sandbox pricing sums
  `billed_cpu_ms`.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS sandbox_usage_events (
      id UUID,
      account_id Int64,
      sandbox_id UUID,
      source LowCardinality(String),
      vcpus UInt16,
      memory_mb UInt32,
      guaranteed_cpu_milli UInt32,
      duration_ms UInt32,
      used_cpu_ms UInt64,
      billed_cpu_ms UInt64,
      inserted_at DateTime64(6)
    ) ENGINE = #{Migration.engine("MergeTree")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (account_id, inserted_at, sandbox_id)
    TTL toDateTime(inserted_at) + INTERVAL 730 DAY
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS sandbox_usage_events")
  end
end
