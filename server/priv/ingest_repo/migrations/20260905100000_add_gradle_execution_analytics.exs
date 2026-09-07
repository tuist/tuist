defmodule Tuist.IngestRepo.Migrations.AddGradleExecutionAnalytics do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE gradle_builds
      ADD COLUMN IF NOT EXISTS telemetry_version UInt16 DEFAULT 0,
      ADD COLUMN IF NOT EXISTS build_options Map(String, String) DEFAULT map(),
      ADD COLUMN IF NOT EXISTS execution_graph String DEFAULT '',
      ADD COLUMN IF NOT EXISTS dependency_chain_duration_ms Nullable(UInt64),
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
      ADD COLUMN IF NOT EXISTS remote_cache_upload_duration_ms Nullable(UInt64),
      ADD COLUMN IF NOT EXISTS on_dependency_chain Nullable(Bool)
    """

    execute """
    ALTER TABLE gradle_tasks ADD PROJECTION IF NOT EXISTS gradle_tasks_by_project
    (SELECT project_id, inserted_at, gradle_build_id, build_path, project_path,
      task_path, task_type, outcome, duration_ms, remote_cache_miss, on_dependency_chain
      ORDER BY (project_id, inserted_at, build_path, project_path, task_path))
    """
  end

  def down do
    execute "ALTER TABLE gradle_tasks DROP PROJECTION gradle_tasks_by_project"

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
      remove :on_dependency_chain
    end

    alter table(:gradle_builds) do
      remove :telemetry_version
      remove :build_options
      remove :execution_graph
      remove :dependency_chain_duration_ms
      remove :tasks_cache_hit_count
    end
  end
end
