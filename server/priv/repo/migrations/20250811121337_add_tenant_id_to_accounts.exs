defmodule Tuist.Repo.Migrations.AddTenantIdToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :tenant_id, :string
    end

    create unique_index(:accounts, [:tenant_id])
  end
end
