defmodule Tuist.Repo.Migrations.CreateRunnerWorkflowJobTransitionEvents do
  use Ecto.Migration

  def change do
    create table(:runner_workflow_job_transition_events) do
      add :workflow_job_id, :bigint, null: false
      add :payload, :map, null: false

      timestamps(type: :timestamptz, updated_at: false)
    end
  end
end
