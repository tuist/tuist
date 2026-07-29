defmodule Tuist.Repo.Migrations.AddArtifactRetentionIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index(:app_builds, [:preview_id, :inserted_at],
                           name: :app_builds_preview_id_inserted_at_index,
                           concurrently: true
                         )
  end
end
