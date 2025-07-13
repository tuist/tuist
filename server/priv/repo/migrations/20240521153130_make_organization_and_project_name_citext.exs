defmodule Tuist.Repo.Migrations.MakeOrganizationAndProjectNameCitext do
  use Ecto.Migration

  def change do
    drop index(:projects, [:name, :account_id], name: "index_projects_on_name_and_account_id")
    drop index(:accounts, [:name], name: "index_accounts_on_name")

    alter table(:projects) do
      modify :name, :citext
    end

    alter table(:accounts) do
      modify :name, :citext
    end

    create unique_index(:projects, [:name, :account_id],
             name: "index_projects_on_name_and_account_id"
           )

    create unique_index(:accounts, [:name], name: "index_accounts_on_name")
  end
end
