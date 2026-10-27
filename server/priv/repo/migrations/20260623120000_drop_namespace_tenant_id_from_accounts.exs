defmodule Tuist.Repo.Migrations.DropNamespaceTenantIdFromAccounts do
  use Ecto.Migration

  # The third-party Namespace runner integration was retired, so the column it
  # populated drops with it. Dropping the column also drops its unique index, so
  # no explicit index drop is needed. Pairs with the removal of the
  # `Account.namespace_tenant_id` schema field in the same change.
  def up do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :namespace_tenant_id, :string
    end
  end

  def down do
    alter table(:accounts) do
      add :namespace_tenant_id, :string
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:accounts, [:namespace_tenant_id])
  end
end
