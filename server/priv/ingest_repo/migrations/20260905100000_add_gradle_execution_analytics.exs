defmodule Tuist.IngestRepo.Migrations.AddGradleExecutionAnalytics do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE gradle_builds
      ADD COLUMN IF NOT EXISTS telemetry_version UInt16 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS tasks_cache_hit_count UInt32 DEFAULT 0
    """

    execute """
    ALTER TABLE gradle_tasks
      ADD COLUMN IF NOT EXISTS build_path String DEFAULT '',
      ADD COLUMN IF NOT EXISTS cacheability LowCardinality(String) DEFAULT 'unknown',
      ADD COLUMN IF NOT EXISTS incremental Nullable(Bool),
      ADD COLUMN IF NOT EXISTS remote_cache_lookup_outcome LowCardinality(String) DEFAULT 'unknown'
    """
  end

  def down do
    alter table(:gradle_tasks) do
      remove :build_path
      remove :cacheability
      remove :incremental
      remove :remote_cache_lookup_outcome
    end

    alter table(:gradle_builds) do
      remove :telemetry_version
      remove :tasks_cache_hit_count
    end
  end
end
