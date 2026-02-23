CREATE TABLE tuist_development.xcode_targets_backup
(
    `id` String,
    `name` String,
    `binary_cache_hash` Nullable(String),
    `binary_cache_hit` Enum8('miss' = 0, 'local' = 1, 'remote' = 2),
    `selective_testing_hash` Nullable(String),
    `selective_testing_hit` Enum8('miss' = 0, 'local' = 1, 'remote' = 2),
    `xcode_project_id` String,
    `inserted_at` DateTime DEFAULT now(),
    `binary_build_duration` Nullable(UInt32),
    INDEX idx_name_ngram name TYPE ngrambf_v1(3, 256, 2, 0) GRANULARITY 4,
    INDEX idx_selective_testing_hash selective_testing_hash TYPE bloom_filter(0.01) GRANULARITY 4,
    INDEX idx_binary_cache_hash binary_cache_hash TYPE bloom_filter(0.01) GRANULARITY 4,
    PROJECTION proj_by_project_and_hit
    (
        SELECT
            id,
            name,
            binary_cache_hash,
            binary_cache_hit,
            binary_build_duration,
            selective_testing_hash,
            selective_testing_hit,
            xcode_project_id,
            inserted_at
        ORDER BY
            xcode_project_id,
            selective_testing_hit,
            binary_cache_hit
    )
)
ENGINE = MergeTree
ORDER BY (xcode_project_id, inserted_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.xcode_targets
(
    `id` String,
    `name` String,
    `binary_cache_hash` Nullable(String),
    `binary_cache_hit` Enum8('miss' = 0, 'local' = 1, 'remote' = 2),
    `binary_build_duration` Nullable(UInt32),
    `selective_testing_hash` Nullable(String),
    `selective_testing_hit` Enum8('miss' = 0, 'local' = 1, 'remote' = 2),
    `xcode_project_id` UUID,
    `command_event_id` UUID,
    `inserted_at` DateTime,
    `product` LowCardinality(String) DEFAULT '',
    `bundle_id` String DEFAULT '',
    `product_name` String DEFAULT '',
    `destinations` Array(LowCardinality(String)) DEFAULT [],
    `sources_hash` String DEFAULT '',
    `resources_hash` String DEFAULT '',
    `copy_files_hash` String DEFAULT '',
    `core_data_models_hash` String DEFAULT '',
    `target_scripts_hash` String DEFAULT '',
    `environment_hash` String DEFAULT '',
    `headers_hash` String DEFAULT '',
    `deployment_target_hash` String DEFAULT '',
    `info_plist_hash` String DEFAULT '',
    `entitlements_hash` String DEFAULT '',
    `dependencies_hash` String DEFAULT '',
    `project_settings_hash` String DEFAULT '',
    `target_settings_hash` String DEFAULT '',
    `buildable_folders_hash` String DEFAULT '',
    `additional_strings` Array(String) DEFAULT [],
    `external_hash` String DEFAULT '',
    INDEX command_event_id_idx command_event_id TYPE bloom_filter GRANULARITY 4,
    INDEX name_text_search_idx name TYPE ngrambf_v1(4, 65536, 3, 0) GRANULARITY 4,
    INDEX idx_selective_testing_minmax selective_testing_hash TYPE minmax GRANULARITY 1,
    INDEX idx_binary_cache_minmax binary_cache_hash TYPE minmax GRANULARITY 1,
    PROJECTION proj_by_command_event
    (
        SELECT *
        ORDER BY command_event_id
    )
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(inserted_at)
ORDER BY (inserted_at, id)
TTL inserted_at + toIntervalDay(30)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.xcode_projects_backup
(
    `id` String,
    `name` String,
    `path` String,
    `xcode_graph_id` String,
    `inserted_at` DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (xcode_graph_id, name, inserted_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.xcode_projects
(
    `id` String,
    `name` String,
    `path` String,
    `xcode_graph_id` UUID,
    `command_event_id` UUID,
    `inserted_at` DateTime
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(inserted_at)
ORDER BY (inserted_at, id)
TTL inserted_at + toIntervalDay(30)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.xcode_graphs
(
    `id` String,
    `name` String,
    `command_event_id` UUID,
    `binary_build_duration` Nullable(UInt32),
    `inserted_at` DateTime
)
ENGINE = MergeTree
ORDER BY (id, inserted_at)
TTL inserted_at + toIntervalDay(30)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.test_suite_runs
(
    `id` UUID,
    `name` String,
    `test_run_id` UUID,
    `test_module_run_id` UUID,
    `status` Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
    `duration` Int32,
    `test_case_count` Int32 DEFAULT 0,
    `avg_test_case_duration` Int32 DEFAULT 0,
    `inserted_at` DateTime64(6) DEFAULT now(),
    `is_flaky` Bool DEFAULT false,
    INDEX idx_test_run_id test_run_id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_test_module_run_id test_module_run_id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_status status TYPE set(3) GRANULARITY 1,
    INDEX idx_duration duration TYPE minmax GRANULARITY 4,
    INDEX idx_name name TYPE bloom_filter GRANULARITY 4
)
ENGINE = ReplacingMergeTree(inserted_at)
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (test_run_id, test_module_run_id, id)
SETTINGS index_granularity = 8192;

CREATE MATERIALIZED VIEW tuist_development.test_runs_analytics_monthly
(
    `project_id` Int64,
    `date` Date,
    `is_ci` Bool,
    `status` Nullable(Int32),
    `run_count` UInt64,
    `total_duration` Int64
)
ENGINE = SummingMergeTree
PARTITION BY toYear(date)
ORDER BY (project_id, date, is_ci, assumeNotNull(status))
SETTINGS index_granularity = 8192
AS SELECT
    project_id,
    toStartOfMonth(ran_at) AS date,
    is_ci,
    status,
    count() AS run_count,
    sum(duration) AS total_duration
FROM tuist_development.command_events
WHERE ((name = 'test') OR ((name = 'xcodebuild') AND ((subcommand = 'test') OR (subcommand = 'test-without-building')))) AND (status IS NOT NULL)
GROUP BY
    project_id,
    toStartOfMonth(ran_at),
    is_ci,
    status;

CREATE MATERIALIZED VIEW tuist_development.test_runs_analytics_daily
(
    `project_id` Int64,
    `date` Date,
    `is_ci` Bool,
    `status` Nullable(Int32),
    `run_count` UInt64,
    `total_duration` Int64
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(date)
ORDER BY (project_id, date, is_ci, assumeNotNull(status))
SETTINGS index_granularity = 8192
AS SELECT
    project_id,
    toDate(ran_at) AS date,
    is_ci,
    status,
    count() AS run_count,
    sum(duration) AS total_duration
FROM tuist_development.command_events
WHERE ((name = 'test') OR ((name = 'xcodebuild') AND ((subcommand = 'test') OR (subcommand = 'test-without-building')))) AND (status IS NOT NULL)
GROUP BY
    project_id,
    toDate(ran_at),
    is_ci,
    status;

CREATE TABLE tuist_development.test_runs
(
    `id` UUID,
    `project_id` Int64,
    `duration` Int32,
    `macos_version` String,
    `xcode_version` String,
    `is_ci` Bool,
    `model_identifier` String,
    `scheme` String,
    `status` LowCardinality(String),
    `git_branch` String,
    `git_commit_sha` String,
    `git_ref` String,
    `account_id` Int64,
    `ran_at` DateTime64(6),
    `inserted_at` DateTime64(6) DEFAULT now(),
    `ci_run_id` String DEFAULT '',
    `ci_project_handle` String DEFAULT '',
    `ci_host` String DEFAULT '',
    `ci_provider` LowCardinality(Nullable(String)),
    `build_run_id` Nullable(UUID),
    `is_flaky` Bool DEFAULT false,
    `build_system` LowCardinality(String) DEFAULT 'xcode',
    `gradle_build_id` Nullable(UUID),
    INDEX idx_duration duration TYPE minmax GRANULARITY 4,
    INDEX idx_scheme scheme TYPE bloom_filter GRANULARITY 4,
    INDEX idx_status status TYPE set(3) GRANULARITY 1
)
ENGINE = ReplacingMergeTree(inserted_at)
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (project_id, id)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.test_module_runs
(
    `id` UUID,
    `name` String,
    `test_run_id` UUID,
    `status` Enum8('success' = 0, 'failure' = 1),
    `duration` Int32,
    `test_suite_count` Int32 DEFAULT 0,
    `test_case_count` Int32 DEFAULT 0,
    `avg_test_case_duration` Int32 DEFAULT 0,
    `inserted_at` DateTime64(6) DEFAULT now(),
    `is_flaky` Bool DEFAULT false,
    INDEX idx_test_run_id test_run_id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_status status TYPE set(2) GRANULARITY 1,
    INDEX idx_duration duration TYPE minmax GRANULARITY 4,
    INDEX idx_name name TYPE bloom_filter GRANULARITY 4
)
ENGINE = ReplacingMergeTree(inserted_at)
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (test_run_id, id)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.test_cases
(
    `id` UUID,
    `name` String,
    `module_name` String DEFAULT '',
    `suite_name` String DEFAULT '',
    `project_id` Int64,
    `last_status` Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
    `last_duration` Int32 DEFAULT 0,
    `last_ran_at` DateTime64(6),
    `inserted_at` DateTime64(6) DEFAULT now(),
    `recent_durations` Array(Int32) DEFAULT [],
    `avg_duration` Int64 DEFAULT 0,
    `is_flaky` Bool DEFAULT false,
    `is_quarantined` Bool DEFAULT 0,
    INDEX idx_id id TYPE bloom_filter GRANULARITY 4
)
ENGINE = ReplacingMergeTree(inserted_at)
ORDER BY (project_id, module_name, suite_name, name, id)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.test_case_runs
(
    `id` UUID,
    `name` String,
    `test_run_id` UUID,
    `test_module_run_id` UUID,
    `test_suite_run_id` UUID,
    `status` Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
    `duration` Int32,
    `module_name` String DEFAULT '',
    `suite_name` String DEFAULT '',
    `inserted_at` DateTime64(6) DEFAULT now(),
    `project_id` Nullable(Int64),
    `is_ci` Bool DEFAULT 0,
    `scheme` String DEFAULT '',
    `account_id` Nullable(Int64),
    `ran_at` Nullable(DateTime64(6)),
    `git_branch` String DEFAULT '',
    `test_case_id` Nullable(UUID),
    `git_commit_sha` String DEFAULT '',
    `is_flaky` Bool DEFAULT false,
    `is_new` Bool DEFAULT 0,
    INDEX idx_test_run_id test_run_id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_test_module_run_id test_module_run_id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_test_suite_run_id test_suite_run_id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_status status TYPE set(3) GRANULARITY 1,
    INDEX idx_duration duration TYPE minmax GRANULARITY 4,
    INDEX idx_name name TYPE bloom_filter GRANULARITY 4,
    INDEX idx_module_name module_name TYPE bloom_filter GRANULARITY 4,
    INDEX idx_suite_name suite_name TYPE bloom_filter GRANULARITY 4,
    INDEX idx_test_case_id test_case_id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_cross_run_flaky (test_case_id, git_commit_sha, is_ci) TYPE bloom_filter GRANULARITY 1,
    PROJECTION proj_by_test_case_id
    (
        SELECT *
        ORDER BY
            test_case_id,
            ran_at
    ),
    PROJECTION proj_by_branch_ci
    (
        SELECT
            git_branch,
            is_ci,
            ran_at,
            test_case_id
        ORDER BY
            git_branch,
            is_ci,
            ran_at,
            test_case_id
    ),
    PROJECTION proj_by_project_analytics
    (
        SELECT
            id,
            project_id,
            inserted_at,
            is_ci,
            status,
            duration
        ORDER BY
            project_id,
            inserted_at
    )
)
ENGINE = ReplacingMergeTree(inserted_at)
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (test_run_id, test_module_run_id, id)
SETTINGS index_granularity = 8192, deduplicate_merge_projection_mode = 'rebuild';

CREATE TABLE tuist_development.test_case_run_repetitions
(
    `id` UUID,
    `test_case_run_id` UUID,
    `repetition_number` Int32,
    `name` String,
    `status` LowCardinality(String),
    `duration` Int32 DEFAULT 0,
    `inserted_at` DateTime64(6) DEFAULT now(),
    INDEX idx_test_case_run_id test_case_run_id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_status status TYPE set(2) GRANULARITY 1
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (test_case_run_id, repetition_number, inserted_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.test_case_run_crash_reports
(
    `id` UUID,
    `exception_type` LowCardinality(String) DEFAULT '',
    `signal` LowCardinality(String) DEFAULT '',
    `exception_subtype` LowCardinality(String) DEFAULT '',
    `triggered_thread_frames` String DEFAULT '',
    `test_case_run_id` UUID,
    `test_case_run_attachment_id` UUID,
    `inserted_at` DateTime64(6) DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (test_case_run_id, id)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.test_case_run_attachments
(
    `id` UUID,
    `test_case_run_id` UUID,
    `file_name` String,
    `inserted_at` DateTime64(6) DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (test_case_run_id, id)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.test_case_failures
(
    `id` UUID,
    `test_case_run_id` UUID,
    `message` String,
    `path` String,
    `line_number` Int32,
    `issue_type` LowCardinality(String),
    `inserted_at` DateTime64(6) DEFAULT now(),
    INDEX idx_test_case_run_id test_case_run_id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_line_number line_number TYPE minmax GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (test_case_run_id, inserted_at, id)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.test_case_events
(
    `id` UUID,
    `test_case_id` UUID,
    `event_type` LowCardinality(String),
    `actor_id` Nullable(Int64),
    `inserted_at` DateTime64(6) DEFAULT now(),
    INDEX idx_test_case_id test_case_id TYPE bloom_filter GRANULARITY 4
)
ENGINE = ReplacingMergeTree(inserted_at)
ORDER BY (test_case_id, event_type, id)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.qa_logs
(
    `project_id` Int64,
    `qa_run_id` UUID,
    `data` String,
    `type` Enum8('usage' = 0, 'tool_call' = 1, 'tool_call_result' = 2, 'message' = 3),
    `timestamp` DateTime,
    `inserted_at` DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(timestamp)
ORDER BY (project_id, qa_run_id, timestamp)
TTL inserted_at + toIntervalDay(14)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.gradle_tasks
(
    `id` UUID,
    `gradle_build_id` UUID,
    `task_path` String,
    `task_type` String DEFAULT '',
    `outcome` LowCardinality(String),
    `cacheable` Bool DEFAULT 0,
    `duration_ms` UInt64 DEFAULT 0,
    `cache_key` String DEFAULT '',
    `cache_artifact_size` Nullable(Int64),
    `started_at` Nullable(DateTime64(6)),
    `project_id` Int64,
    `inserted_at` DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (gradle_build_id, task_path, inserted_at)
TTL inserted_at + toIntervalDay(90)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.gradle_cache_events
(
    `id` UUID,
    `action` Enum8('upload' = 0, 'download' = 1),
    `cache_key` String,
    `size` Int64,
    `duration_ms` UInt64 DEFAULT 0,
    `is_hit` Bool DEFAULT 1,
    `project_id` Int64,
    `account_handle` String,
    `project_handle` String,
    `is_ci` Bool DEFAULT 0,
    `gradle_build_id` Nullable(UUID),
    `inserted_at` DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (project_id, action, inserted_at)
TTL inserted_at + toIntervalDay(90)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.gradle_builds
(
    `id` UUID,
    `project_id` Int64,
    `account_id` Int64,
    `duration_ms` UInt64,
    `gradle_version` String DEFAULT '',
    `java_version` String DEFAULT '',
    `is_ci` Bool DEFAULT 0,
    `status` Enum8('success' = 0, 'failure' = 1, 'cancelled' = 2),
    `git_branch` String DEFAULT '',
    `git_commit_sha` String DEFAULT '',
    `git_ref` String DEFAULT '',
    `root_project_name` String DEFAULT '',
    `tasks_local_hit_count` UInt32 DEFAULT 0,
    `tasks_remote_hit_count` UInt32 DEFAULT 0,
    `tasks_up_to_date_count` UInt32 DEFAULT 0,
    `tasks_executed_count` UInt32 DEFAULT 0,
    `tasks_failed_count` UInt32 DEFAULT 0,
    `tasks_skipped_count` UInt32 DEFAULT 0,
    `tasks_no_source_count` UInt32 DEFAULT 0,
    `cacheable_tasks_count` UInt32 DEFAULT 0,
    `inserted_at` DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (project_id, inserted_at)
TTL inserted_at + toIntervalDay(90)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.command_events
(
    `id` UUID,
    `legacy_id` UInt64 DEFAULT abs(rand64()),
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
    `hit_rate` Nullable(Float32) DEFAULT multiIf(cacheable_targets_count > 0, ((local_cache_hits_count + remote_cache_hits_count) / cacheable_targets_count) * 100, NULL),
    `test_run_id` Nullable(UUID),
    `cache_endpoint` String DEFAULT '',
    INDEX idx_name name TYPE bloom_filter GRANULARITY 4,
    INDEX idx_git_branch git_branch TYPE bloom_filter GRANULARITY 16,
    INDEX idx_git_ref git_ref TYPE bloom_filter GRANULARITY 16,
    INDEX idx_git_commit_sha git_commit_sha TYPE bloom_filter GRANULARITY 16,
    INDEX idx_build_run_id build_run_id TYPE bloom_filter GRANULARITY 8,
    INDEX idx_id id TYPE bloom_filter GRANULARITY 4,
    INDEX idx_status status TYPE minmax GRANULARITY 64,
    INDEX idx_is_ci is_ci TYPE minmax GRANULARITY 128,
    INDEX idx_user_id user_id TYPE minmax GRANULARITY 32,
    INDEX idx_hit_rate hit_rate TYPE minmax GRANULARITY 16,
    INDEX idx_test_run_id test_run_id TYPE bloom_filter GRANULARITY 8
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(ran_at)
ORDER BY (project_id, name, ran_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.cas_outputs
(
    `node_id` String,
    `checksum` String,
    `size` UInt64,
    `duration` UInt64,
    `compressed_size` UInt64,
    `operation` Enum8('download' = 0, 'upload' = 1),
    `build_run_id` UUID,
    `inserted_at` DateTime DEFAULT now(),
    `type` LowCardinality(String) DEFAULT 'unknown'
)
ENGINE = MergeTree
ORDER BY (build_run_id, node_id, operation, inserted_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.cas_events
(
    `id` UUID,
    `action` Enum8('upload' = 0, 'download' = 1),
    `size` Int64,
    `cas_id` String,
    `project_id` Int64,
    `inserted_at` DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (project_id, action, inserted_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.cas_entries
(
    `id` UUID,
    `cas_id` String,
    `value` String,
    `project_id` Int64,
    `inserted_at` DateTime DEFAULT now()
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (cas_id, project_id, inserted_at)
TTL inserted_at + toIntervalDay(90)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.cacheable_tasks
(
    `type` Enum8('clang' = 0, 'swift' = 1),
    `status` Enum8('hit_local' = 0, 'hit_remote' = 1, 'miss' = 2),
    `key` String,
    `build_run_id` UUID,
    `inserted_at` DateTime DEFAULT now(),
    `read_duration` Nullable(Float64),
    `write_duration` Nullable(Float64),
    `description` Nullable(String),
    `cas_output_node_ids` Array(String)
)
ENGINE = MergeTree
ORDER BY (build_run_id, key, status, inserted_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.build_targets
(
    `name` String,
    `project` String,
    `compilation_duration` UInt64,
    `build_duration` UInt64,
    `build_run_id` UUID,
    `status` Enum8('success' = 0, 'failure' = 1),
    `inserted_at` DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (build_run_id, compilation_duration, build_duration, name, project, status, inserted_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.build_runs
(
    `id` UUID,
    `duration` Int32,
    `project_id` Int64,
    `account_id` Int64,
    `macos_version` String DEFAULT '',
    `xcode_version` String DEFAULT '',
    `is_ci` Bool DEFAULT false,
    `model_identifier` String DEFAULT '',
    `scheme` String DEFAULT '',
    `status` LowCardinality(String) DEFAULT '',
    `category` LowCardinality(String) DEFAULT '',
    `configuration` String DEFAULT '',
    `git_branch` String DEFAULT '',
    `git_commit_sha` String DEFAULT '',
    `git_ref` String DEFAULT '',
    `ci_run_id` String DEFAULT '',
    `ci_project_handle` String DEFAULT '',
    `ci_host` String DEFAULT '',
    `ci_provider` LowCardinality(String) DEFAULT '',
    `cacheable_task_remote_hits_count` Int32 DEFAULT 0,
    `cacheable_task_local_hits_count` Int32 DEFAULT 0,
    `cacheable_tasks_count` Int32 DEFAULT 0,
    `custom_tags` Array(String) DEFAULT [],
    `custom_values` Map(String, String) DEFAULT map(),
    `inserted_at` DateTime64(6)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(inserted_at)
ORDER BY (project_id, inserted_at, id)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.build_issues
(
    `type` Enum8('warning' = 0, 'error' = 1),
    `target` String,
    `project` String,
    `title` String,
    `signature` String,
    `path` String,
    `message` String,
    `starting_line` UInt64,
    `ending_line` UInt64,
    `starting_column` UInt64,
    `ending_column` UInt64,
    `build_run_id` UUID,
    `inserted_at` DateTime DEFAULT now(),
    `step_type` Enum8('c_compilation' = 0, 'swift_compilation' = 1, 'script_execution' = 2, 'create_static_library' = 3, 'linker' = 4, 'copy_swift_libs' = 5, 'compile_assets_catalog' = 6, 'compile_storyboard' = 7, 'write_auxiliary_file' = 8, 'link_storyboards' = 9, 'copy_resource_file' = 10, 'merge_swift_module' = 11, 'xib_compilation' = 12, 'swift_aggregated_compilation' = 13, 'precompile_bridging_header' = 14, 'other' = 15, 'validate_embedded_binary' = 16, 'validate' = 17)
)
ENGINE = MergeTree
ORDER BY (build_run_id, inserted_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.build_files
(
    `type` Enum8('swift' = 0, 'c' = 1),
    `target` String,
    `project` String,
    `path` String,
    `compilation_duration` UInt64,
    `build_run_id` UUID,
    `inserted_at` DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (build_run_id, compilation_duration, path, inserted_at)
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.`.inner_id.e726f4ee-c8ad-4fcc-83b6-6056a610343d`
(
    `project_id` Int64,
    `date` Date,
    `is_ci` Bool,
    `status` Nullable(Int32),
    `run_count` UInt64,
    `total_duration` Int64
)
ENGINE = SummingMergeTree
PARTITION BY toYear(date)
ORDER BY (project_id, date, is_ci, assumeNotNull(status))
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.`.inner_id.00a7d9bc-d72e-4729-b667-72bdf2f6d7ea`
(
    `project_id` Int64,
    `date` Date,
    `is_ci` Bool,
    `status` Nullable(Int32),
    `run_count` UInt64,
    `total_duration` Int64
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(date)
ORDER BY (project_id, date, is_ci, assumeNotNull(status))
SETTINGS index_granularity = 8192;

CREATE TABLE tuist_development.schema_migrations
(
    `version` Int64,
    `inserted_at` DateTime
)
ENGINE = MergeTree
PRIMARY KEY version
ORDER BY version
SETTINGS index_granularity = 8192;

INSERT INTO "tuist_development"."schema_migrations" (version, inserted_at) VALUES
(20250528130330,'2026-02-17 09:21:29'),
(20250602150450,'2026-02-17 09:21:29'),
(20250604103840,'2026-02-17 09:21:29'),
(20250612082641,'2026-02-17 09:21:29'),
(20250612082654,'2026-02-17 09:21:29'),
(20250612082706,'2026-02-17 09:21:29'),
(20250616172309,'2026-02-17 09:21:29'),
(20250630111612,'2026-02-17 09:21:29'),
(20250701124940,'2026-02-17 09:21:29'),
(20250701125025,'2026-02-17 09:21:29'),
(20250701125026,'2026-02-17 09:21:29'),
(20250702083709,'2026-02-17 09:21:29'),
(20250702083710,'2026-02-17 09:21:29'),
(20250708112228,'2026-02-17 09:21:29'),
(20250715093853,'2026-02-17 09:21:29'),
(20250715155316,'2026-02-17 09:21:30'),
(20250715193142,'2026-02-17 09:21:30'),
(20250716104544,'2026-02-17 09:21:30'),
(20250721130110,'2026-02-17 09:21:30'),
(20250728120556,'2026-02-17 09:21:30'),
(20250811155755,'2026-02-17 09:21:30'),
(20251010170219,'2026-02-17 09:21:30'),
(20251028151804,'2026-02-17 09:21:30'),
(20251105141225,'2026-02-17 09:21:30'),
(20251106143925,'2026-02-17 09:21:30'),
(20251107172941,'2026-02-17 09:21:30'),
(20251108122707,'2026-02-17 09:21:30'),
(20251111102756,'2026-02-17 09:21:30'),
(20251112142931,'2026-02-17 09:21:30'),
(20251113120819,'2026-02-17 09:21:30'),
(20251117120000,'2026-02-17 09:21:30'),
(20251117153551,'2026-02-17 09:21:30'),
(20251117154146,'2026-02-17 09:21:30'),
(20251117154300,'2026-02-17 09:21:30'),
(20251117191146,'2026-02-17 09:21:30'),
(20251117201055,'2026-02-17 09:21:30'),
(20251117202642,'2026-02-17 09:21:30'),
(20251118211224,'2026-02-17 09:21:30'),
(20251126143809,'2026-02-17 09:21:30'),
(20251126151610,'2026-02-17 09:21:30'),
(20251127103046,'2026-02-17 09:21:30'),
(20251127150000,'2026-02-17 09:21:30'),
(20251127150001,'2026-02-17 09:21:30'),
(20251201203244,'2026-02-17 09:21:30'),
(20251203162956,'2026-02-17 09:21:30'),
(20251205110312,'2026-02-17 09:21:30'),
(20251205140000,'2026-02-17 09:21:30'),
(20251208125255,'2026-02-17 09:21:30'),
(20251218142614,'2026-02-17 09:21:30'),
(20260109100001,'2026-02-17 09:21:30'),
(20260112160000,'2026-02-17 09:21:30'),
(20260113100000,'2026-02-17 09:21:30'),
(20260114100000,'2026-02-17 09:21:30'),
(20260116111209,'2026-02-17 09:21:30'),
(20260116134753,'2026-02-17 09:21:30'),
(20260116134754,'2026-02-17 09:21:30'),
(20260119100000,'2026-02-17 09:21:30'),
(20260120101402,'2026-02-17 09:21:30'),
(20260121091606,'2026-02-17 09:21:30'),
(20260121091607,'2026-02-17 09:21:30'),
(20260123150000,'2026-02-17 09:21:30'),
(20260123160000,'2026-02-17 09:21:30'),
(20260124111832,'2026-02-17 09:21:30'),
(20260124111905,'2026-02-17 09:21:30'),
(20260131183703,'2026-02-17 09:21:30'),
(20260131183704,'2026-02-17 09:21:30'),
(20260204150000,'2026-02-17 09:21:30'),
(20260204150001,'2026-02-17 09:21:30'),
(20260204150002,'2026-02-17 09:21:30'),
(20260204173039,'2026-02-17 09:21:30'),
(20260211124936,'2026-02-17 09:21:30'),
(20260211150000,'2026-02-17 09:21:30'),
(20260212160000,'2026-02-17 09:21:30'),
(20260213100000,'2026-02-17 09:21:30'),
(20260214120000,'2026-02-17 09:21:30'),
(20260216120000,'2026-02-17 09:21:30'),
(20260217120000,'2026-02-17 09:21:30');
