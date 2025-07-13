defmodule Tuist.Repo.Migrations.IndexNameGitRefAndRemoteUrlOriginOnCommandEvents do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:command_events, [:name, :git_ref, :git_remote_url_origin])
  end
end
