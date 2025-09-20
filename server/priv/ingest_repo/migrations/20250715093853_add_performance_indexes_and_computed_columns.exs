defmodule Tuist.ClickHouseRepo.Migrations.AddPerformanceIndexesAndComputedColumns do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE command_events ADD COLUMN cacheable_targets_count UInt32 DEFAULT length(cacheable_targets)"
    )

    execute(
      "ALTER TABLE command_events ADD COLUMN local_cache_hits_count UInt32 DEFAULT length(local_cache_target_hits)"
    )

    execute(
      "ALTER TABLE command_events ADD COLUMN remote_cache_hits_count UInt32 DEFAULT length(remote_cache_target_hits)"
    )

    execute(
      "ALTER TABLE command_events ADD COLUMN test_targets_count UInt32 DEFAULT length(test_targets)"
    )

    execute(
      "ALTER TABLE command_events ADD COLUMN local_test_hits_count UInt32 DEFAULT length(local_test_target_hits)"
    )

    execute(
      "ALTER TABLE command_events ADD COLUMN remote_test_hits_count UInt32 DEFAULT length(remote_test_target_hits)"
    )

    execute("""
    ALTER TABLE command_events ADD COLUMN hit_rate Nullable(Float32) DEFAULT 
      CASE 
        WHEN cacheable_targets_count > 0 
        THEN (local_cache_hits_count + remote_cache_hits_count) / cacheable_targets_count * 100
        ELSE NULL 
      END
    """)

    execute("ALTER TABLE command_events ADD INDEX idx_name name TYPE bloom_filter GRANULARITY 1")

    execute(
      "ALTER TABLE command_events ADD INDEX idx_git_branch git_branch TYPE bloom_filter GRANULARITY 1"
    )

    execute(
      "ALTER TABLE command_events ADD INDEX idx_git_ref git_ref TYPE bloom_filter GRANULARITY 1"
    )

    execute(
      "ALTER TABLE command_events ADD INDEX idx_git_commit_sha git_commit_sha TYPE bloom_filter GRANULARITY 1"
    )

    execute("ALTER TABLE command_events ADD INDEX idx_status status TYPE minmax GRANULARITY 1")
    execute("ALTER TABLE command_events ADD INDEX idx_is_ci is_ci TYPE minmax GRANULARITY 1")
    execute("ALTER TABLE command_events ADD INDEX idx_user_id user_id TYPE minmax GRANULARITY 1")

    execute(
      "ALTER TABLE command_events ADD INDEX idx_project_id project_id TYPE minmax GRANULARITY 1"
    )

    execute("ALTER TABLE command_events ADD INDEX idx_name_set name TYPE set(100) GRANULARITY 1")
  end

  def down do
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_name_set")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_project_id")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_user_id")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_is_ci")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_status")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_git_commit_sha")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_git_ref")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_git_branch")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_name")

    execute("ALTER TABLE command_events DROP COLUMN hit_rate")
    execute("ALTER TABLE command_events DROP COLUMN remote_test_hits_count")
    execute("ALTER TABLE command_events DROP COLUMN local_test_hits_count")
    execute("ALTER TABLE command_events DROP COLUMN test_targets_count")
    execute("ALTER TABLE command_events DROP COLUMN remote_cache_hits_count")
    execute("ALTER TABLE command_events DROP COLUMN local_cache_hits_count")
    execute("ALTER TABLE command_events DROP COLUMN cacheable_targets_count")
  end
end
