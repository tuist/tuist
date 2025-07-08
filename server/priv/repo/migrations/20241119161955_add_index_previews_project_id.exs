defmodule Tuist.Repo.Migrations.AddIndexPreviewsProjectId do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:previews, [:project_id], concurrently: true)
  end
end
