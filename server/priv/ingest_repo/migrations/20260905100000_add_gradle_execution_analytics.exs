defmodule Tuist.IngestRepo.Migrations.AddGradleExecutionAnalytics do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE gradle_builds
      ADD COLUMN IF NOT EXISTS tasks_cache_hit_count UInt32 DEFAULT 0
    """

    execute """
    ALTER TABLE gradle_tasks
      ADD COLUMN IF NOT EXISTS build_path String DEFAULT '',
      ADD COLUMN IF NOT EXISTS cacheability LowCardinality(String) DEFAULT '',
      ADD COLUMN IF NOT EXISTS incremental Nullable(Bool),
      ADD COLUMN IF NOT EXISTS remote_cache_lookup_outcome LowCardinality(String) DEFAULT 'unknown',
      ADD COLUMN IF NOT EXISTS remote_cache_download_duration_ms Nullable(UInt64),
      ADD COLUMN IF NOT EXISTS remote_cache_upload_duration_ms Nullable(UInt64)
    """
  end

  def down do
    alter table(:gradle_tasks) do
      remove :build_path
      remove :cacheability
      remove :incremental
      remove :remote_cache_lookup_outcome
      remove :remote_cache_download_duration_ms
      remove :remote_cache_upload_duration_ms
    end

    alter table(:gradle_builds) do
      remove :tasks_cache_hit_count
    end
  end
end
