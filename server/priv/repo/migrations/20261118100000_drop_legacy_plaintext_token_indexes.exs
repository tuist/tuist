defmodule Tuist.Repo.Migrations.DropLegacyPlaintextTokenIndexes do
  @moduledoc """
  First half of dropping the former plaintext `users.token` and
  `projects.token` columns: their unique indexes go concurrently, so the
  column drop that follows only touches the catalog.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    drop_if_exists unique_index(:users, [:token], name: :index_users_on_token, concurrently: true)

    drop_if_exists unique_index(:projects, [:token],
                     name: :index_projects_on_token,
                     concurrently: true
                   )
  end

  def down do
    create_if_not_exists unique_index(:users, [:token],
                           name: :index_users_on_token,
                           concurrently: true
                         )

    create_if_not_exists unique_index(:projects, [:token],
                           name: :index_projects_on_token,
                           concurrently: true
                         )
  end
end
