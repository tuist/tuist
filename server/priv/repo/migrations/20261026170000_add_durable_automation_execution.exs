defmodule Tuist.Repo.Migrations.AddDurableAutomationExecution do
  use Ecto.Migration

  def change do
    alter table(:automation_alerts) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :durable_execution, :boolean, null: false, default: false
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :execution_revision, :bigint, null: false, default: 0
    end

    create table(:automation_evaluations, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :alert_id, references(:automation_alerts, type: :uuid, on_delete: :delete_all),
        null: false

      add :revision, :binary, null: false
      add :state, :string, null: false, default: "running"
      add :scope, :map, null: false, default: %{}
      add :cursor, :map
      add :evaluated_at, :timestamptz, null: false
      add :baseline, :boolean, null: false
      timestamps(type: :timestamptz)
    end

    # New, empty tables: these indexes cannot block existing writers.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:automation_evaluations, [:alert_id], where: "state = 'running'")

    create table(:automation_test_states, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :alert_id, references(:automation_alerts, type: :uuid, on_delete: :delete_all),
        null: false

      add :generation, :integer, null: false
      add :test_case_id, :uuid, null: false
      add :status, :string, null: false
      add :triggered_at, :timestamptz
      add :sequence, :bigint, null: false, default: 0
      add :pending_transition_id, :uuid
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:automation_test_states, [:alert_id, :generation, :test_case_id])

    create table(:automation_transitions, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :state_id, references(:automation_test_states, type: :uuid, on_delete: :delete_all),
        null: false

      add :revision, :binary, null: false
      add :sequence, :bigint, null: false
      add :status, :string, null: false
      add :phase, :string, null: false, default: "pending"
      add :actions, {:array, :map}, null: false, default: []
      add :event_types, {:array, :string}, null: false, default: []
      add :snapshot, :map
      add :occurred_at, :timestamptz
      add :error, :text
      add :depth, :integer, null: false, default: 0
      add :source_id, :uuid
      add :fanout_done, :boolean, null: false, default: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:automation_transitions, [:state_id, :sequence])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:automation_transitions, [:state_id, :source_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:automation_transitions, [:phase, :inserted_at])

    create table(:automation_deliveries, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :transition_id,
          references(:automation_transitions, type: :uuid, on_delete: :delete_all), null: false

      add :position, :integer, null: false
      add :action, :map, null: false
      add :state, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :error, :text
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:automation_deliveries, [:transition_id, :position])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:automation_deliveries, [:state, :inserted_at])

    create table(:automation_delivery_destinations, primary_key: false) do
      add :key, :string, primary_key: true
      add :available_at, :timestamptz, null: false
    end
  end
end
