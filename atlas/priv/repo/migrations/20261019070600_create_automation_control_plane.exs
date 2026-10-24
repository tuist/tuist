defmodule Atlas.Repo.Migrations.CreateAutomationControlPlane do
  use Ecto.Migration

  def change do
    create table(:automation_workflows, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :description, :text
      add :language, :text, null: false
      add :source, :text, null: false
      add :input_schema, :map, null: false
      add :created_by_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      timestamps(type: :timestamptz)
    end

    create table(:automation_revisions, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :workflow_id, references(:automation_workflows, type: :uuid, on_delete: :restrict),
        null: false

      add :published_by_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :number, :integer, null: false
      add :plan, :map, null: false
      add :source, :text, null: false
      add :language, :text, null: false
      add :input_schema, :map, null: false
      timestamps(type: :timestamptz, updated_at: false)
    end

    create unique_index(:automation_revisions, [:workflow_id, :number])

    alter table(:automation_workflows) do
      add :published_revision_id,
          references(:automation_revisions, type: :uuid, on_delete: :restrict)
    end

    create table(:automation_behaviors, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :description, :text
      add :type, :text, null: false
      add :configuration, :map, null: false
      add :input_schema, :map, null: false
      add :output_schema, :map, null: false
      add :created_by_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      timestamps(type: :timestamptz)
    end

    create table(:automation_runs, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :revision_id, references(:automation_revisions, type: :uuid, on_delete: :restrict),
        null: false

      add :initiated_by_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :status, :text, null: false
      add :trigger, :text, null: false
      add :admission_key, :text
      add :input, :map, null: false
      add :outputs, :map, null: false
      add :cursor, :integer, null: false, default: 0
      add :last_error, :text
      add :completed_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create unique_index(:automation_runs, [:admission_key])
    create index(:automation_runs, [:revision_id, :inserted_at])
    create index(:automation_runs, [:status])

    create table(:automation_attempts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :run_id, references(:automation_runs, type: :uuid, on_delete: :delete_all), null: false
      add :step_id, :text, null: false
      add :status, :text, null: false
      add :executor, :text, null: false
      add :input, :map
      add :output, :map
      add :error, :text
      timestamps(type: :timestamptz)
    end

    create index(:automation_attempts, [:run_id])

    create table(:automation_approvals, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :run_id, references(:automation_runs, type: :uuid, on_delete: :delete_all), null: false
      add :reviewer_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :decided_by_id, references(:users, type: :uuid, on_delete: :restrict)
      add :step_id, :text, null: false
      add :status, :text, null: false
      add :payload, :map, null: false
      add :decided_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create unique_index(:automation_approvals, [:run_id, :step_id])
    create index(:automation_approvals, [:reviewer_id, :status])

    create table(:automation_triggers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :kind, :text, null: false
      add :enabled, :boolean, null: false, default: true
      add :cron, :text
      add :next_run_at, :timestamptz
      add :token_hash, :binary
      add :input, :map, null: false

      add :revision_id, references(:automation_revisions, type: :uuid, on_delete: :restrict),
        null: false

      add :execution_user_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      timestamps(type: :timestamptz)
    end

    create index(:automation_triggers, [:kind, :enabled, :next_run_at])
  end
end
