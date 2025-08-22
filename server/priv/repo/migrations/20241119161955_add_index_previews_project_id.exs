defmodule Tuist.Repo.Migrations.AddIndexPreviewsProjectId do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create index(:previews, [:project_id], concurrently: true)
  end

  def down do
    drop_if_exists index(:previews, [:project_id])
  end
end
