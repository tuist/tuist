defmodule Tuist.Repo.Migrations.AddIndexSuggestions do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:subscriptions, [:account_id], concurrently: true)
    create index(:cache_action_items, [:hash], concurrently: true)
    create index(:organizations, [:sso_organization_id], concurrently: true)
  end
end
