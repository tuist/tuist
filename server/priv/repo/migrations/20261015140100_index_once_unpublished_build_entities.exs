defmodule Tuist.Repo.Migrations.IndexOnceUnpublishedBuildEntities do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:once_runs, [:finalized_at, :id],
             name: :once_runs_unpublished_build_entities_index,
             where:
               "finalization IN ('finalized', 'lost') AND build_entities_published_at IS NULL",
             concurrently: true
           )
  end
end
