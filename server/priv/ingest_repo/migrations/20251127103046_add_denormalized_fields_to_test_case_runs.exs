defmodule Tuist.IngestRepo.Migrations.AddDenormalizedFieldsToTestCaseRuns do
  use Ecto.Migration

  def change do
    alter table(:test_case_runs) do
      add :project_id, :"Nullable(Int64)"
      add :is_ci, :"Nullable(Bool)"
      add :scheme, :"Nullable(String)"
      add :account_id, :"Nullable(Int64)"
      add :ran_at, :"Nullable(DateTime64(6))"
      add :git_branch, :"Nullable(String)"
    end
  end
end
