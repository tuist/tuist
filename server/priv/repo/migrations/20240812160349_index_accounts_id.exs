defmodule Tuist.Repo.Migrations.IndexAccountsId do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:accounts, [:id])
  end
end
