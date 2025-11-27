defmodule Tuist.IngestRepo.Migrations.AddDenormalizedFieldsToTestCaseRuns do
  use Ecto.Migration

  def change do
    alter table(:test_case_runs) do
      add :project_id, :"Nullable(Int64)"
      add :is_ci, :Bool, default: false
      add :scheme, :String, default: ""
      add :account_id, :"Nullable(Int64)"
      add :ran_at, :"Nullable(DateTime64(6))"
      add :git_branch, :String, default: ""
    end
  end
end
