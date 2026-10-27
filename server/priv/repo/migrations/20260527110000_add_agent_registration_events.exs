defmodule Tuist.Repo.Migrations.AddAgentRegistrationEvents do
  use Ecto.Migration

  def change do
    create table(:agent_registration_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :agent_registration_id,
          references(:agent_registrations, type: :uuid, on_delete: :delete_all), null: false

      add :event_type, :string, null: false
      add :actor_ip, :string
      add :claimed_by_user_id, references(:users, on_delete: :nilify_all)
      add :metadata, :map, null: false, default: %{}
      add :occurred_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:agent_registration_events, [:agent_registration_id, :occurred_at])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:agent_registration_events, [:event_type, :occurred_at])
  end
end
