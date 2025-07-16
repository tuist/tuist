defmodule Tuist.ClickHouseRepo.Migrations.ChangeCommandEventsPrimaryKey do
  use Ecto.Migration

  def up do
    legacy_id_default =
      if Tuist.Environment.dev?() || Tuist.Environment.test?(),
        do: "abs(rand64())",
        # Serial IDs require Zookeeper, which we are not using in dev/test environments. Therefore, only run it in deployment environments.
        else: "generateSerialID('command_events_legacy_id')"

    execute("""
    CREATE TABLE command_events_new
    (
        `id` UUID,
        `legacy_id` UInt64 DEFAULT #{legacy_id_default},
        `legacy_artifact_path` Bool DEFAULT false,
        `name` String,
        `subcommand` Nullable(String),
        `command_arguments` Nullable(String),
        `duration` Int32,
        `client_id` String,
        `tuist_version` String,
        `swift_version` String,
        `macos_version` String,
        `project_id` Int64,
        `created_at` DateTime64(6),
        `updated_at` DateTime64(6),
        `cacheable_targets` Array(String),
        `local_cache_target_hits` Array(String),
        `remote_cache_target_hits` Array(String),
        `is_ci` Bool DEFAULT false,
        `test_targets` Array(String),
        `local_test_target_hits` Array(String),
        `remote_test_target_hits` Array(String),
        `status` Nullable(Int32) DEFAULT 0,
        `error_message` Nullable(String),
        `user_id` Nullable(Int32),
        `remote_cache_target_hits_count` Nullable(Int32) DEFAULT 0,
        `remote_test_target_hits_count` Nullable(Int32) DEFAULT 0,
        `git_commit_sha` Nullable(String),
        `git_ref` Nullable(String),
        `preview_id` Nullable(UUID),
        `git_branch` Nullable(String),
        `ran_at` DateTime64(6),
        `build_run_id` Nullable(UUID),
        `cacheable_targets_count` UInt32 DEFAULT length(cacheable_targets),
        `local_cache_hits_count` UInt32 DEFAULT length(local_cache_target_hits),
        `remote_cache_hits_count` UInt32 DEFAULT length(remote_cache_target_hits),
        `test_targets_count` UInt32 DEFAULT length(test_targets),
        `local_test_hits_count` UInt32 DEFAULT length(local_test_target_hits),
        `remote_test_hits_count` UInt32 DEFAULT length(remote_test_target_hits),
        `hit_rate` Nullable(Float32) DEFAULT
          CASE
            WHEN cacheable_targets_count > 0
            THEN (local_cache_hits_count + remote_cache_hits_count) / cacheable_targets_count * 100
            ELSE NULL
          END
    )
    ENGINE = MergeTree
    PARTITION BY toYYYYMM(ran_at)
    ORDER BY (project_id, name, ran_at)
    SETTINGS index_granularity = 8192
    """)

    execute("""
    INSERT INTO command_events_new
    SELECT
        id, legacy_id, legacy_artifact_path,
        COALESCE(name, '') as name,
        subcommand, command_arguments,
        duration, client_id, tuist_version, swift_version, macos_version,
        project_id, created_at, updated_at, cacheable_targets,
        local_cache_target_hits, remote_cache_target_hits, is_ci,
        test_targets, local_test_target_hits, remote_test_target_hits,
        status, error_message, user_id, remote_cache_target_hits_count,
        remote_test_target_hits_count, git_commit_sha, git_ref, preview_id,
        git_branch,
        COALESCE(ran_at, created_at) as ran_at,
        build_run_id,
        cacheable_targets_count, local_cache_hits_count, remote_cache_hits_count,
        test_targets_count, local_test_hits_count, remote_test_hits_count, hit_rate
    FROM command_events
    """)

    execute("DROP TABLE command_events")

    execute("RENAME TABLE command_events_new TO command_events")

    # Essential bloom filters for high-cardinality fields
    execute("ALTER TABLE command_events ADD INDEX idx_name name TYPE bloom_filter GRANULARITY 4")

    execute(
      "ALTER TABLE command_events ADD INDEX idx_git_branch git_branch TYPE bloom_filter GRANULARITY 16"
    )

    execute(
      "ALTER TABLE command_events ADD INDEX idx_git_ref git_ref TYPE bloom_filter GRANULARITY 16"
    )

    execute(
      "ALTER TABLE command_events ADD INDEX idx_git_commit_sha git_commit_sha TYPE bloom_filter GRANULARITY 16"
    )

    execute(
      "ALTER TABLE command_events ADD INDEX idx_build_run_id build_run_id TYPE bloom_filter GRANULARITY 8"
    )

    execute("ALTER TABLE command_events ADD INDEX idx_id id TYPE bloom_filter GRANULARITY 4")

    # MinMax indexes for low-cardinality fields and ranges
    execute("ALTER TABLE command_events ADD INDEX idx_status status TYPE minmax GRANULARITY 64")
    execute("ALTER TABLE command_events ADD INDEX idx_is_ci is_ci TYPE minmax GRANULARITY 128")
    execute("ALTER TABLE command_events ADD INDEX idx_user_id user_id TYPE minmax GRANULARITY 32")

    execute(
      "ALTER TABLE command_events ADD INDEX idx_hit_rate hit_rate TYPE minmax GRANULARITY 16"
    )
  end

  def down do
    :ok
  end
end
