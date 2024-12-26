defmodule Tuist.Repo.Migrations.AddRepositoryFullHandleToPackages do
  use Ecto.Migration

  def up do
    alter table(:packages) do
      add :repository_full_handle, :string
    end

    flush()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "UPDATE packages SET repository_full_handle = scope || '/' || name"
  end

  def down do
    alter table(:packages) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :repository_full_handle
    end
  end
end
