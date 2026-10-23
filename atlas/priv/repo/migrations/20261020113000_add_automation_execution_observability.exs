defmodule Atlas.Repo.Migrations.AddAutomationExecutionObservability do
  use Ecto.Migration

  def change do
    alter table(:automation_runs) do
      add :trace_id, :text
      add :trace_flags, :integer, null: false, default: 1
      add :span_id, :text
      add :trace_started_at, :timestamptz
      add :trace_completed_at, :timestamptz
      add :event_sequence, :bigint, null: false, default: 0
    end

    alter table(:automation_attempts) do
      add :started_at, :timestamptz
      add :completed_at, :timestamptz
      add :duration_ms, :bigint
      add :execution_duration_ms, :bigint
      add :wait_started_at, :timestamptz
      add :wait_duration_ms, :bigint
      add :trace_id, :text
      add :span_id, :text
      add :parent_span_id, :text
      add :job_id, :bigint
      add :job_attempt, :integer
      add :diagnostic, :map
    end

    create unique_index(:automation_attempts, [:run_id],
             where: "status = 'running'",
             name: :automation_attempts_one_running
           )

    create table(:automation_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :run_id, references(:automation_runs, type: :uuid, on_delete: :delete_all), null: false
      add :attempt_id, references(:automation_attempts, type: :uuid, on_delete: :nilify_all)
      add :sequence, :bigint, null: false
      add :event, :text, null: false
      add :level, :text, null: false
      add :message, :text, null: false
      add :step_id, :text
      add :trace_id, :text
      add :span_id, :text
      add :metadata, :map, null: false
      timestamps(type: :timestamptz, updated_at: false)
    end

    create unique_index(:automation_events, [:run_id, :sequence])
  end
end
