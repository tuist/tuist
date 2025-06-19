defmodule Tuist.Repo.Migrations.AddUniqueIndexesForRoleAssignments do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create unique_index(:users_roles, [:role_id],
             name: :users_roles_role_id_unique_index,
             concurrently: true
           )
  end
end
