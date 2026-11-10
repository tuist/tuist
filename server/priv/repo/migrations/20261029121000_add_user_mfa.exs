defmodule Tuist.Repo.Migrations.AddUserMFA do
  use Ecto.Migration

  def up do
    # Every authenticated request reads and checkpoints users_tokens. Fail the
    # migration instead of queuing those requests behind its brief exclusive lock.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "SET LOCAL lock_timeout = '5s'"

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

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "SET LOCAL lock_timeout = '5s'"

    alter table(:users_tokens) do
      # Only binaries from this release read the column; stop them first.
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :mfa_verified_at
    end

    # Destroys enrollment and recovery state; the self-host guide requires an
    # encrypted backup and stopped readers before rolling back.
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:user_mfa)
  end
end
