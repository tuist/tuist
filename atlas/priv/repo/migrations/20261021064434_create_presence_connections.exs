defmodule Atlas.Repo.Migrations.CreatePresenceConnections do
  use Ecto.Migration

  def change do
    create table(:presence_connections, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :connection_id, :uuid, primary_key: true
      add :location, :string

      add :expires_at, :timestamptz,
        null: false,
        default: fragment("clock_timestamp() + interval '20 seconds'")
    end

    create index(:presence_connections, [:expires_at])
  end
end
