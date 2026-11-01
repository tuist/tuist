defmodule Tuist.Repo.Migrations.AddUserMFA do
  use Ecto.Migration

  def change do
    create table(:user_mfa) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :secret, :binary, null: false
      add :enrollment_session_hash, :binary, null: false
      add :enrollment_expires_at, :timestamptz, null: false
      add :confirmed_at, :timestamptz
      add :last_used_at, :timestamptz
      add :recovery_code_hashes, {:array, :binary}, null: false, default: []
      add :failed_attempts, :integer, null: false, default: 0
      add :attempt_window_started_at, :timestamptz
    end

    # This table is created empty in the same transaction; no existing
    # readers or writers can be blocked while its unique index is built.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:user_mfa, [:user_id])

    alter table(:users_tokens) do
      add :mfa_verified_at, :timestamptz
    end
  end
end
