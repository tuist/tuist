defmodule Tuist.Repo.Migrations.CreateRunnerWorkflowJobTransitionEvents do
  use Ecto.Migration

  def change do
    create table(:runner_workflow_job_transition_events) do
      add :workflow_job_id, :bigint, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :payload, :map, null: false

      timestamps(type: :timestamptz, updated_at: false)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_workflow_job_transition_events, [:account_id])
  end
end
