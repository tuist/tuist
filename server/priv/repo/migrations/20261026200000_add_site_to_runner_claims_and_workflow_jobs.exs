defmodule Tuist.Repo.Migrations.AddSiteToRunnerClaimsAndWorkflowJobs do
  use Ecto.Migration

  def change do
    alter table(:runner_claims) do
      add :site, :string
    end

    alter table(:runner_workflow_jobs) do
      add :site, :string
    end
  end
end
