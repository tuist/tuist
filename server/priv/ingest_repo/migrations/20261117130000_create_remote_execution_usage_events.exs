defmodule Tuist.IngestRepo.Migrations.CreateRemoteExecutionUsageEvents do
  @moduledoc """
  One row per remote execution VM that ran an action: the account and project
  it ran for, how it was dispatched (`scheduled` by the account scheduler or
  `leased` to a direct caller), the VM's shape, and how long the node measured
  the executor running in it. VMs are single-use, so `sandbox_id` identifies
  the execution. The Usage page prices these rows.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS remote_execution_usage_events (
      id UUID,
      account_id Int64,
      project_id Int64,
      sandbox_id UUID,
      mode LowCardinality(String),
      vcpus UInt16,
      memory_mb UInt32,
      duration_ms UInt32,
      inserted_at DateTime64(6)
    ) ENGINE = #{Migration.engine("MergeTree")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (account_id, inserted_at, sandbox_id)
    TTL toDateTime(inserted_at) + INTERVAL 730 DAY
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS remote_execution_usage_events")
  end
end
