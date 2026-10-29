defmodule Atlas.Repo.Migrations.CreateAgentSessions do
  use Ecto.Migration

  def change do
    create table(:agent_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent, :string, null: false
      add :prompt, :text, null: false
      add :status, :string, null: false, default: "running"
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :duration_ms, :bigint
      add :result, :map
      add :error, :text

      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:agent_sessions, [:agent])
    create index(:agent_sessions, [:status])
    create index(:agent_sessions, [:started_at])
    create index(:agent_sessions, [:account_id])

    create table(:agent_session_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :agent_session_id,
          references(:agent_sessions, type: :binary_id, on_delete: :delete_all), null: false

      add :type, :string, null: false
      add :name, :string
      add :phase, :string, null: false
      add :duration_ms, :bigint
      add :metadata, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(updated_at: false)
    end

    create index(:agent_session_events, [:agent_session_id, :occurred_at])
    create index(:agent_session_events, [:type, :phase])
  end
end
