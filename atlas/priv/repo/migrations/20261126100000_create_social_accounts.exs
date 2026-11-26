defmodule Atlas.Repo.Migrations.CreateSocialAccounts do
  use Ecto.Migration

  # Social accounts belong to Atlas, not to the person who connected them, so
  # X grants move out of the personal `user_connections`. The encrypted token
  # columns are copied as stored ciphertext; both use the same vault.
  def up do
    create table(:social_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :platform, :string, null: false
      add :external_id, :string, null: false
      add :handle, :string, null: false
      add :kind, :string, null: false
      add :access_token, :binary, null: false
      add :refresh_token, :binary
      add :scopes, {:array, :string}, null: false, default: []
      add :expires_at, :utc_datetime
      add :needs_authorization, :boolean, null: false, default: false
      add :connected_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:social_accounts, [:platform, :external_id])

    execute("""
    INSERT INTO social_accounts
      (id, platform, external_id, handle, kind, access_token, refresh_token, scopes, expires_at,
       needs_authorization, connected_by_id, inserted_at, updated_at)
    SELECT gen_random_uuid(), 'x', provider_user_id, account_name, 'brand', access_token, refresh_token,
           scopes, expires_at, needs_authorization, user_id, inserted_at, updated_at
    FROM user_connections
    WHERE provider = 'x'
    ON CONFLICT (platform, external_id) DO NOTHING
    """)

    execute("DELETE FROM user_connections WHERE provider = 'x'")
  end

  # Rolling back drops the grants; accounts must be connected again.
  def down do
    drop table(:social_accounts)
  end
end
