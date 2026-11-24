defmodule Tuist.Repo.Migrations.RenameGuildPushAppToLuft do
  use Ecto.Migration

  # Tuist Guild is now Luft, so its push registrations move from `app = 'guild'`
  # to `app = 'luft'`. The table holds at most ten live rows per user and app.
  def up do
    drop constraint(:push_installations, :supported_app)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "UPDATE push_installations SET app = 'luft' WHERE app = 'guild'"

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:push_installations, :supported_app, check: "app IN ('tuist', 'luft')")
  end

  def down do
    drop constraint(:push_installations, :supported_app)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "UPDATE push_installations SET app = 'guild' WHERE app = 'luft'"

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:push_installations, :supported_app, check: "app IN ('tuist', 'guild')")
  end
end
