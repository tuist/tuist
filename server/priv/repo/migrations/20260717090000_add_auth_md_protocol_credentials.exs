defmodule Tuist.Repo.Migrations.AddAuthMdProtocolCredentials do
  use Ecto.Migration

  def change do
    alter table(:agent_registrations) do
      add :last_polled_at, :timestamptz
    end

    create table(:agent_auth_credentials, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :agent_registration_id,
          references(:agent_registrations, type: :uuid, on_delete: :delete_all), null: false

      add :jti, :string, null: false
      add :expires_at, :timestamptz, null: false
      add :revoked_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:agent_auth_credentials, [:jti])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:agent_auth_credentials, [:agent_registration_id, :revoked_at])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:agent_auth_credentials, [:expires_at])
  end
end
