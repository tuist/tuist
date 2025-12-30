defmodule Tuist.Repo.Migrations.AddCiMetadataToBuildRuns do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      add :ci_run_id, :string
      add :ci_project_handle, :string
      add :ci_host, :string
      add :ci_provider, :integer
    end
  end
end
