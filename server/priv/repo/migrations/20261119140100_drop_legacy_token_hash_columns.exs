defmodule Tuist.Repo.Migrations.DropLegacyTokenHashColumns do
  @moduledoc """
  Drops `token_hash` and `legacy_token_last_used_at` from `users` and
  `projects`. Every legacy token was revoked on 2026-11-19, leaving both
  columns empty, and the release before this one stopped reading or writing
  them. `down` brings the columns back empty; the tokens stay revoked.
  """
  use Ecto.Migration

  def up do
    # Every authenticated request reads users or projects. Fail the migration
    # instead of queuing those requests behind its brief exclusive lock.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "SET LOCAL lock_timeout = '5s'"

    for table <- [:users, :projects] do
      alter table(table) do
        # excellent_migrations:safety-assured-for-next-line column_removed
        remove :token_hash
        # excellent_migrations:safety-assured-for-next-line column_removed
        remove :legacy_token_last_used_at
      end
    end
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "SET LOCAL lock_timeout = '5s'"

    for table <- [:users, :projects] do
      alter table(table) do
        add :token_hash, :binary
        add :legacy_token_last_used_at, :timestamptz
      end
    end
  end
end
