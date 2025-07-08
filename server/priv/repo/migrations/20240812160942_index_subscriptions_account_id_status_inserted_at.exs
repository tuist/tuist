defmodule Tuist.Repo.Migrations.IndexSubscriptionsAccountIdStatusInsertedAt do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:subscriptions, [:account_id, :status, :inserted_at])
  end
end
