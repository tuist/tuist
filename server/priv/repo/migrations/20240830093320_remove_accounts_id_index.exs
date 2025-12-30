defmodule Tuist.Repo.Migrations.RemoveAccountsIdIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    drop index("accounts", [:id], concurrently: true)
  end
end
