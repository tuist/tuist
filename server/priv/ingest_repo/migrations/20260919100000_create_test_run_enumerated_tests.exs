defmodule Tuist.IngestRepo.Migrations.CreateTestRunEnumeratedTests do
  @moduledoc """
  The tests a run could have executed, as the client listed them without
  running any (`xcodebuild -enumerate-tests`). A run's filters do not narrow
  the list, so it is the candidate set a selective run chose from: what says
  which tests a run left out, and later what test selection plans over.

  Keyed by the test case's stable id, the one `test_case_runs` carries, so
  "enumerated and not run" is a difference of two sets. Retained like the
  coverage file detail.
  """
  use Ecto.Migration

  alias Tuist.Environment
  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    retention = Environment.coverage_retention_days()

    execute("""
    CREATE TABLE IF NOT EXISTS test_run_enumerated_tests
    (
      `project_id` Int64,
      `test_run_id` UUID,
      `test_case_id` UUID,
      `module_name` String,
      `suite_name` String DEFAULT '',
      `name` String,
      `enabled` Bool DEFAULT true,
      `inserted_at` DateTime64(6) DEFAULT now()
    )
    ENGINE = #{Migration.engine("ReplacingMergeTree(inserted_at)")}
    ORDER BY (project_id, test_run_id, test_case_id)
    TTL toDateTime(inserted_at) + INTERVAL #{retention.files} DAY
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS test_run_enumerated_tests")
  end
end
