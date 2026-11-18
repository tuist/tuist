defmodule Tuist.Repo.Migrations.CreateUserPasskeys do
  use Ecto.Migration

  def change do
    create table(:user_passkeys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :user_handle, :binary, null: false
      add :sign_count, :bigint, null: false, default: 0
      add :aaguid, :binary
      add :transports, {:array, :string}, null: false, default: []
      add :backup_eligible, :boolean, null: false, default: false
      add :backed_up, :boolean, null: false, default: false
      add :last_used_at, :timestamptz
      add :last_challenge_issued_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # The table is created empty in the same transaction; no existing
    # readers or writers can be blocked while its indexes are built.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:user_passkeys, [:credential_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:user_passkeys, [:user_id])
  end
end
