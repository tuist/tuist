defmodule Tuist.IngestRepo.Migrations.CreateBazelInvocationStarts do
  @moduledoc """
  One row per Bazel invocation Kura saw start, sent as soon as the
  invocation's target patterns arrive. An invocation is running while it has
  a start and no `bazel_invocations` row; Kura drops an invocation it has not
  seen finish after 24 hours, so starts are only kept for two days.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS bazel_invocation_starts (
      project_id Int64,
      invocation_id String,
      command LowCardinality(String),
      target_patterns Array(String),
      git_branch String,
      git_commit_sha String,
      is_ci Bool,
      started_at DateTime64(3),
      inserted_at DateTime64(6)
    ) ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    ORDER BY (project_id, invocation_id)
    TTL toDateTime(inserted_at) + INTERVAL 2 DAY
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS bazel_invocation_starts")
  end
end
