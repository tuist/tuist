defmodule Tuist.Repo.Migrations.AddTenantIdToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :namespace_tenant_id, :string
    end

    create unique_index(:accounts, [:namespace_tenant_id])
  end
end
