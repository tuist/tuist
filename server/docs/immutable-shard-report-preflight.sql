-- Run directly against the application's authoritative read endpoint using its read credentials.
-- These checks analyze queries without scanning historical execution data.
SELECT hostName() AS server, currentDatabase() AS database, version() AS version;

SELECT throwIf(count() != 14, 'Missing immutable shard reporting views')
FROM system.tables
WHERE database = currentDatabase() AND engine = 'View'
  AND name IN (
    'latest_shard_test_reports',
    'reported_test_case_runs',
    'reported_test_module_runs',
    'reported_test_suite_runs',
    'reported_test_run_errors',
    'reported_test_run_destinations',
    'reported_test_run_stress_candidates',
    'reported_test_case_failures',
    'reported_test_case_run_arguments',
    'reported_test_case_run_repetitions',
    'reported_test_case_run_attachments',
    'reported_test_run_summaries',
    'test_run_summaries',
    'shard_run_summaries'
  );

-- PLAN expands typed views. QUERY TREE alone can trust their declared columns
-- and miss broken references in the underlying SELECT.
EXPLAIN PLAN SELECT reporting_version, assignments FROM shard_plans LIMIT 1;
EXPLAIN PLAN SELECT * FROM latest_shard_test_reports LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_case_runs LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_module_runs LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_suite_runs LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_run_errors LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_run_destinations LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_run_stress_candidates LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_case_failures LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_case_run_arguments LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_case_run_repetitions LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_case_run_attachments LIMIT 1;
EXPLAIN PLAN SELECT * FROM reported_test_run_summaries LIMIT 1;
EXPLAIN PLAN SELECT * FROM test_run_summaries LIMIT 1;
EXPLAIN PLAN SELECT * FROM shard_run_summaries LIMIT 1;
