defmodule Tuist.Repo.Migrations.AddTenantIdToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :tenant_id, :string
    end
  end
end