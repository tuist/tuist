defmodule Tuist.IngestRepo.Migrations.AddCiFieldsToTestRuns do
  use Ecto.Migration

  def change do
    alter table(:test_runs) do
      add :ci_run_id, :string, default: ""
      add :ci_project_handle, :string, default: ""
      add :ci_host, :string, default: ""
      add :ci_provider, :"LowCardinality(Nullable(String))"
    end
  end
end
