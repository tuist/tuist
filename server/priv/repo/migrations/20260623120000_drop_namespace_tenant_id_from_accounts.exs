defmodule Tuist.Repo.Migrations.DropNamespaceTenantIdFromAccounts do
  use Ecto.Migration

  # The third-party Namespace runner integration was retired, so the column it
  # populated (and its unique index) drops with it. Pairs with the removal of
  # the `Account.namespace_tenant_id` schema field in the same change.
  def up do
    drop_if_exists unique_index(:accounts, [:namespace_tenant_id])

    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :namespace_tenant_id, :string
    end
  end

  def down do
    alter table(:accounts) do
      add :namespace_tenant_id, :string
    end

    create unique_index(:accounts, [:namespace_tenant_id])
  end
end
