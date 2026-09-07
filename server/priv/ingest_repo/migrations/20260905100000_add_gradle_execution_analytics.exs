defmodule Tuist.IngestRepo.Migrations.AddGradleExecutionAnalytics do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE gradle_builds
      ADD COLUMN IF NOT EXISTS telemetry_version UInt16 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS build_options Map(String, String) DEFAULT map(),
      ADD COLUMN IF NOT EXISTS tasks_cache_hit_count UInt32 DEFAULT 0
    """

    execute """
    ALTER TABLE gradle_tasks
      ADD COLUMN IF NOT EXISTS build_path String DEFAULT '',
      ADD COLUMN IF NOT EXISTS project_path String DEFAULT '',
      ADD COLUMN IF NOT EXISTS cacheability LowCardinality(String) DEFAULT 'unknown',
      ADD COLUMN IF NOT EXISTS caching_disabled_reason String DEFAULT '',
      ADD COLUMN IF NOT EXISTS execution_reasons Array(String) DEFAULT [],
      ADD COLUMN IF NOT EXISTS incremental Nullable(Bool),
      ADD COLUMN IF NOT EXISTS remote_cache_lookup_outcome LowCardinality(String) DEFAULT 'unknown',
      ADD COLUMN IF NOT EXISTS remote_cache_lookup_duration_ms Nullable(UInt64),
      ADD COLUMN IF NOT EXISTS remote_cache_download_duration_ms Nullable(UInt64),
      ADD COLUMN IF NOT EXISTS remote_cache_upload_duration_ms Nullable(UInt64)
    """
  end

  def down do
    alter table(:gradle_tasks) do
      remove :build_path
      remove :project_path
      remove :cacheability
      remove :caching_disabled_reason
      remove :execution_reasons
      remove :incremental
      remove :remote_cache_lookup_outcome
      remove :remote_cache_lookup_duration_ms
      remove :remote_cache_download_duration_ms
      remove :remote_cache_upload_duration_ms
    end

    alter table(:gradle_builds) do
      remove :telemetry_version
      remove :build_options
      remove :tasks_cache_hit_count
    end
  end
end
