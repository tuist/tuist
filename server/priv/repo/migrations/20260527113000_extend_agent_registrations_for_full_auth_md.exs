defmodule Tuist.Repo.Migrations.ExtendAgentRegistrationsForFullAuthMd do
  use Ecto.Migration

  def change do
    alter table(:agent_registrations) do
      add :revoked_at, :timestamptz
      add :issuer, :string
      add :subject, :string
      add :audience, :string
      add :client_id, :string
      add :assertion_jti, :string
      add :credential_jti, :string
      add :account_token_id, references(:account_tokens, type: :uuid, on_delete: :nilify_all)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:agent_registrations, [:account_token_id])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:agent_registrations, [:issuer, :subject, :audience])

    create table(:agent_auth_jtis, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :issuer, :string, null: false
      add :jti, :string, null: false
      add :expires_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:agent_auth_jtis, [:issuer, :jti])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:agent_auth_jtis, [:expires_at])
  end
end
