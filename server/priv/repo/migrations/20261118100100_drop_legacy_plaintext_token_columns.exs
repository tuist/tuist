defmodule Tuist.Repo.Migrations.DropLegacyPlaintextTokenColumns do
  @moduledoc """
  Drops the former plaintext `users.token` and `projects.token` columns.
  Legacy tokens are looked up by `token_hash`; the columns were emptied on
  2026-11-16, and the release before this one stopped reading or writing them.
  `down` brings the columns back empty; the tokens cannot be recovered.
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
        remove :token
      end
    end
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "SET LOCAL lock_timeout = '5s'"

    for table <- [:users, :projects] do
      alter table(table) do
        add :token, :string, size: 100
      end
    end
  end
end
