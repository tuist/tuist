defmodule Tuist.Repo.Migrations.DropLegacyTokenHashIndexes do
  @moduledoc """
  First half of dropping the retired legacy token columns: the partial unique
  indexes on `users.token_hash` and `projects.token_hash` go concurrently, so
  the column drop that follows only touches the catalog.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    drop_if_exists unique_index(:users, [:token_hash],
                     name: :users_token_hash_index,
                     concurrently: true
                   )

    drop_if_exists unique_index(:projects, [:token_hash],
                     name: :projects_token_hash_index,
                     concurrently: true
                   )
  end

  def down do
    create_if_not_exists unique_index(:users, [:token_hash],
                           name: :users_token_hash_index,
                           where: "token_hash IS NOT NULL",
                           concurrently: true
                         )

    create_if_not_exists unique_index(:projects, [:token_hash],
                           name: :projects_token_hash_index,
                           where: "token_hash IS NOT NULL",
                           concurrently: true
                         )
  end
end
