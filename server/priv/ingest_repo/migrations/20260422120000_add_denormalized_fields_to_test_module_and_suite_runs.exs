defmodule Tuist.IngestRepo.Migrations.AddDenormalizedFieldsToTestModuleAndSuiteRuns do
  @moduledoc """
  Adds `project_id`, `is_ci`, `git_branch`, and `ran_at` to `test_module_runs`
  and `test_suite_runs` so queries that currently join through `test_runs` to
  filter by project/branch/ran_at can filter directly, without a subquery.

  Columns are nullable for existing rows; a later migration backfills them
  from `test_runs` and a follow-up migration marks them non-nullable once
  backfill is verified. Same pattern used for `test_case_runs` in
  20251127103046_add_denormalized_fields_to_test_case_runs.exs.
  """
  use Ecto.Migration

  def change do
    alter table(:test_module_runs) do
      add :project_id, :"Nullable(Int64)"
      add :is_ci, :Bool, default: false
      add :git_branch, :String, default: ""
      add :ran_at, :"Nullable(DateTime64(6))"
    end

    alter table(:test_suite_runs) do
      add :project_id, :"Nullable(Int64)"
      add :is_ci, :Bool, default: false
      add :git_branch, :String, default: ""
      add :ran_at, :"Nullable(DateTime64(6))"
    end
  end
end
