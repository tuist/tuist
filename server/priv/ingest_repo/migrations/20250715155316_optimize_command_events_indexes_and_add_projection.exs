defmodule Tuist.ClickHouseRepo.Migrations.OptimizeCommandEventsIndexesAndAddProjection do
  use Ecto.Migration

  def up do
    # These were created in previous migrations with suboptimal granularity settings.
    # Granularity in ClickHouse determines how many table granules (blocks of rows) are covered by a single index entry.
    # With the default index_granularity of 8192 rows per granule, GRANULARITY 1 means one index entry per granule,
    # which creates excessive index entries, consuming more memory and slowing down index scans.
    # Higher granularity values (4, 8, 16, etc.) mean fewer index entries covering more data, providing better performance.
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_name")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_git_branch")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_git_ref")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_git_commit_sha")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_status")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_is_ci")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_user_id")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_project_id")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_name_set")

    # Bloom filters
    # Bloom filters are probabilistic data structures that efficiently test whether an element is in a set.
    # They're ideal for string columns where we need to check equality (e.g., name = 'cache').
    # They can have false positives but never false negatives, making them perfect for filtering before reading data.

    # Medium cardinality
    execute("ALTER TABLE command_events ADD INDEX idx_name name TYPE bloom_filter GRANULARITY 4")

    # High cardinality
    execute(
      "ALTER TABLE command_events ADD INDEX idx_git_branch git_branch TYPE bloom_filter GRANULARITY 8"
    )

    execute(
      "ALTER TABLE command_events ADD INDEX idx_git_ref git_ref TYPE bloom_filter GRANULARITY 8"
    )

    execute(
      "ALTER TABLE command_events ADD INDEX idx_git_commit_sha git_commit_sha TYPE bloom_filter GRANULARITY 8"
    )

    # MinMax indexes
    # MinMax indexes store the minimum and maximum values for each granule of data.
    # They're perfect for numeric columns and low-cardinality columns where we filter by ranges or equality.
    # ClickHouse can skip entire granules if the searched value is outside the min/max range.

    # Low cardinality
    execute("ALTER TABLE command_events ADD INDEX idx_status status TYPE minmax GRANULARITY 32")
    execute("ALTER TABLE command_events ADD INDEX idx_is_ci is_ci TYPE minmax GRANULARITY 64")

    # Medium cardinality
    execute("ALTER TABLE command_events ADD INDEX idx_user_id user_id TYPE minmax GRANULARITY 16")

    execute(
      "ALTER TABLE command_events ADD INDEX idx_project_id project_id TYPE minmax GRANULARITY 8"
    )

    execute(
      "ALTER TABLE command_events ADD INDEX idx_hit_rate hit_rate TYPE minmax GRANULARITY 8"
    )

    execute(
      "ALTER TABLE command_events ADD INDEX idx_project_name (project_id, name) TYPE minmax GRANULARITY 4"
    )

    execute("""
    ALTER TABLE command_events ADD PROJECTION projection_by_project_name_hit_rate
    (
      SELECT
        id, legacy_id, legacy_artifact_path, name, subcommand, command_arguments,
        duration, client_id, tuist_version, swift_version, macos_version,
        project_id, is_ci, status, error_message, cacheable_targets,
        local_cache_target_hits, remote_cache_target_hits, remote_cache_target_hits_count,
        test_targets, local_test_target_hits, remote_test_target_hits,
        remote_test_target_hits_count, git_commit_sha, git_ref, git_branch,
        user_id, preview_id, build_run_id, ran_at, created_at, updated_at,
        cacheable_targets_count, local_cache_hits_count, remote_cache_hits_count,
        test_targets_count, local_test_hits_count, remote_test_hits_count, hit_rate
      ORDER BY project_id, name, hit_rate
    )
    """)

    execute(
      "ALTER TABLE command_events MATERIALIZE PROJECTION projection_by_project_name_hit_rate"
    )
  end

  def down do
    execute(
      "ALTER TABLE command_events DROP PROJECTION IF EXISTS projection_by_project_name_hit_rate"
    )

    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_hit_rate")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_project_name")

    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_name")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_git_branch")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_git_ref")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_git_commit_sha")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_status")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_is_ci")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_user_id")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_project_id")
    execute("ALTER TABLE command_events DROP INDEX IF EXISTS idx_name_set")
  end
end
