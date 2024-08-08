defmodule Tuist.Repo.Migrations.OwnerToUserAndOrganization do
  use Ecto.Migration

  def up do
    alter table(:accounts) do
      add(:user_id, references(:users, on_delete: :delete_all))
      add(:organization_id, references(:organizations, on_delete: :delete_all))
    end

    drop unique_index(:accounts, [:owner_id, :owner_type],
           name: :index_accounts_on_owner_id_and_owner_type
         )

    create unique_index(:accounts, [:user_id])
    create unique_index(:accounts, [:organization_id])

    execute("UPDATE accounts SET user_id = owner_id WHERE owner_type = 'User';")
    execute("UPDATE accounts SET organization_id = owner_id WHERE owner_type = 'Organization';")

    alter table(:accounts) do
      remove(:owner_id)
      remove(:owner_type)
    end
  end

  def down do
    alter table(:accounts) do
      add(:owner_id, :integer)
      add(:owner_type, :string)
    end

    execute(
      "UPDATE accounts SET owner_id = user_id, owner_type = 'User' WHERE user_id IS NOT NULL;"
    )

    execute(
      "UPDATE accounts SET owner_id = organization_id, owner_type = 'Organization' WHERE organization_id IS NOT NULL;"
    )

    drop unique_index(:accounts, [:user_id])
    drop unique_index(:accounts, [:organization_id])

    alter table(:accounts) do
      remove(:user_id)
      remove(:organization_id)
    end

    create unique_index(:accounts, [:owner_id, :owner_type],
             name: :index_accounts_on_owner_id_and_owner_type
           )
  end
end
