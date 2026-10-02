defmodule Tuist.Repo.Migrations.AddLowerRepositoryFullHandleIndexToVcsConnections do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:vcs_connections, ["lower(repository_full_handle)"],
             name: :vcs_connections_lower_repository_full_handle_index,
             concurrently: true
           )
  end
end
