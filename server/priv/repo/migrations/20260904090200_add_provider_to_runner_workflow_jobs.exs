defmodule Tuist.Repo.Migrations.AddProviderToRunnerWorkflowJobs do
  use Ecto.Migration

  # Every row written before this migration came from a GitHub
  # `workflow_job` webhook, so the default backfills the existing table
  # correctly without a rewrite.
  def change do
    alter table(:runner_workflow_jobs) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :provider, :string, null: false, default: "github"
    end
  end
end
