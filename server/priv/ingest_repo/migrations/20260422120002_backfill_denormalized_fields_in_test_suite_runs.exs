defmodule Tuist.IngestRepo.Migrations.BackfillDenormalizedFieldsInTestSuiteRuns do
  @moduledoc """
  Backfills `project_id`, `is_ci`, `git_branch`, and `ran_at` on existing
  `test_suite_runs` rows by joining against `test_runs`. Mirrors the
  `test_module_runs` backfill — see that migration's moduledoc for the
  strategy.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true
  @dict_name "test_runs_denorm_dict_for_suite_runs"

  def up do
    IngestRepo.query!("DROP DICTIONARY IF EXISTS #{@dict_name}")

    IngestRepo.query!("""
    CREATE DICTIONARY #{@dict_name} (
      id UUID,
      project_id Int64,
      is_ci Bool,
      git_branch String,
      ran_at DateTime64(6)
    )
    PRIMARY KEY id
    SOURCE(CLICKHOUSE(TABLE 'test_runs'))
    LAYOUT(HASHED())
    LIFETIME(0)
    """)

    Logger.info("Starting test_suite_runs denormalized backfill mutation")

    IngestRepo.query!(
      """
      ALTER TABLE test_suite_runs
      UPDATE
        project_id = dictGet('#{@dict_name}', 'project_id', test_run_id),
        is_ci = dictGet('#{@dict_name}', 'is_ci', test_run_id),
        git_branch = dictGet('#{@dict_name}', 'git_branch', test_run_id),
        ran_at = dictGet('#{@dict_name}', 'ran_at', test_run_id)
      WHERE project_id IS NULL
        AND dictHas('#{@dict_name}', test_run_id)
      SETTINGS mutations_sync = 1
      """,
      [],
      timeout: :infinity
    )

    Logger.info("Finished test_suite_runs denormalized backfill mutation")

    IngestRepo.query!("DROP DICTIONARY #{@dict_name}")
  end

  def down do
    :ok
  end
end
