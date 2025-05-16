defmodule Tuist.Repo.Migrations.AddBundlesProjectIdGitRefIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:bundles, [:project_id, :git_ref], concurrently: true)
  end
end
