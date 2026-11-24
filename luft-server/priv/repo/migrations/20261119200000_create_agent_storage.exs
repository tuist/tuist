defmodule LuftServer.Repo.Migrations.CreateAgentStorage do
  use Ecto.Migration

  def change do
    create table(:agent_sessions, primary_key: false) do
      add :id, :text, primary_key: true
      add :kind, :text, null: false
      add :wanted, :boolean, null: false, default: false
      add :wanted_at, :timestamptz
      add :want_seq, :bigint, null: false, default: 0
      add :epoch, :bigint, null: false, default: 0
      add :host, :text
      add :lease_expires_at, :timestamptz
      add :deleted_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create index(:agent_sessions, [:wanted_at], where: "wanted")
    create index(:agent_sessions, [:host])
    create index(:agent_sessions, [:deleted_at], where: "deleted_at IS NOT NULL")

    create table(:agent_objects, primary_key: false) do
      add :key, :text, primary_key: true
      add :body, :binary, null: false
    end
  end
end
