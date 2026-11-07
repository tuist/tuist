defmodule Tuist.IngestRepo.Migrations.CreateTestRunSelectiveTestingCounts do
  @moduledoc """
  How many tests each Xcode test run with selective testing was asked for and
  how many of them selective testing skipped
  (`Tuist.Tests.SelectiveTestingCounts`). A run's skipped targets only become
  known once its command event reports them, after the run itself was stored,
  so the counts live beside `test_runs` rather than in it. A recount (the
  command event and the processed result bundle can each trigger one) replaces
  the run's row: merges keep the newest insertion.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists table(:test_run_selective_testing_counts,
                           primary_key: false,
                           engine: Migration.engine("ReplacingMergeTree(inserted_at)"),
                           options:
                             "PARTITION BY toYYYYMM(ran_at) ORDER BY (project_id, ran_at, test_run_id)"
                         ) do
      add :test_run_id, :UUID
      add :project_id, :Int64
      add :ran_at, :"DateTime64(6)"
      add :is_ci, :Bool
      add :scheme, :String
      add :requested_test_count, :UInt32
      add :skipped_test_count, :UInt32
      add :skipped_module_count, :UInt32
      add :skipped_modules_without_history, :UInt32
      add :inserted_at, :"DateTime64(6)"
    end
  end

  def down do
    drop_if_exists table(:test_run_selective_testing_counts)
  end
end
