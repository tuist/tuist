defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunHashes do
  @moduledoc """
  Backing table for hash-based cross-run flakiness detection.

  Today flakiness is detected per git commit (`test_case_runs_by_commit`):
  the same commit + scheme producing both a pass and a fail flags a test
  case as flaky. This table extends detection to the *selective-testing
  hash* — the per-target hash that already covers a test target's content
  and its transitive dependencies. When a test case runs at the same hash
  (i.e. nothing affecting that module changed, even across commits) and the
  outcome differs from a previous run, it is flaky. That lets a single
  failing CI run prove flakiness when an earlier run at the identical hash
  passed.

  The hash is not known when `test_case_runs` are ingested — it arrives
  later with the command event and lands on `xcode_targets`. So this is a
  standalone table written by `Tuist.Tests.detect_flaky_tests_by_hash/2`
  (off command-event ingestion), not a materialized view over
  `test_case_runs`. It stays narrow and is ordered to make the lookup
  "prior CI runs of this test case at this hash"
  (`project_id, selective_testing_hash, is_ci, scheme, test_case_id`) a
  short prefix scan. The caller re-fetches full rows from `test_case_runs`
  by `id` only for the small flaky subset.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_run_hashes (
      project_id Int64,
      selective_testing_hash String,
      scheme String,
      test_case_id UUID,
      status Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
      is_ci Bool DEFAULT false,
      test_case_run_id UUID,
      inserted_at DateTime64(6)
    ) ENGINE = ReplacingMergeTree(inserted_at)
    ORDER BY (project_id, selective_testing_hash, is_ci, scheme, test_case_id, test_case_run_id)
    """)
  end

  def down do
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_run_hashes")
  end
end
