defmodule Atlas.Repo.Migrations.AddParentAccountToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :parent_account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:accounts, [:parent_account_id])

    create constraint(:accounts, :accounts_parent_account_not_self,
             check: "parent_account_id IS NULL OR parent_account_id <> id"
           )
  end
end
