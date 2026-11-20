defmodule Tuist.IngestRepo.Migrations.CreateRemoteExecutionActions do
  @moduledoc """
  One row per action the execution gateway ran remotely, as the gateway saw
  it: the Bazel invocation, target and mnemonic from the client's request
  metadata, the command (arguments, environment with secret-looking values
  masked, working directory, platform and declared outputs), how it was
  dispatched and on which VM, the executor's phase timestamps, its exit code
  and the start of its stdout and stderr. Fields are bounded by the gateway
  and the server. Diagnostics only: usage is metered in
  `remote_execution_usage_events`.

  `operation_id` identifies an execution, so a record the gateway delivers
  twice collapses into one row.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS remote_execution_actions (
      operation_id UUID,
      account_id Int64,
      project_id Int64,
      invocation_id String,
      action_hash String,
      action_size Int64,
      tool_name LowCardinality(String),
      tool_version LowCardinality(String),
      mnemonic LowCardinality(String),
      target String,
      configuration_id String,
      execution_path LowCardinality(String),
      sandbox_id String,
      worker String,
      memory_gb UInt16,
      timeout_ms UInt64,
      do_not_cache Bool,
      cached_result Bool,
      arguments Array(String),
      arguments_truncated Bool,
      environment_names Array(String),
      environment_values Array(String),
      working_directory String,
      platform_names Array(String),
      platform_values Array(String),
      output_paths Array(String),
      output_count UInt32,
      status_code Int32,
      status_message String,
      exit_code Int32,
      queued_at Nullable(DateTime64(6)),
      worker_start_at Nullable(DateTime64(6)),
      input_fetch_start_at Nullable(DateTime64(6)),
      input_fetch_completed_at Nullable(DateTime64(6)),
      execution_start_at Nullable(DateTime64(6)),
      execution_completed_at Nullable(DateTime64(6)),
      output_upload_start_at Nullable(DateTime64(6)),
      output_upload_completed_at Nullable(DateTime64(6)),
      worker_completed_at Nullable(DateTime64(6)),
      stdout String,
      stdout_size UInt64,
      stdout_truncated Bool,
      stderr String,
      stderr_size UInt64,
      stderr_truncated Bool,
      inserted_at DateTime64(6)
    ) ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    PARTITION BY toYYYYMM(inserted_at)
    ORDER BY (project_id, invocation_id, operation_id)
    TTL toDateTime(inserted_at) + INTERVAL 90 DAY
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS remote_execution_actions")
  end
end
