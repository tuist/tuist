defmodule TuistOps.Repo.Migrations.AddWorkflowRunMetadataToPreviews do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      add :workflow_run_name, :string
      add :workflow_run_url, :string
    end
  end
end
