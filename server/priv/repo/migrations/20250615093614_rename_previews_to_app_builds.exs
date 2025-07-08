defmodule Tuist.Repo.Migrations.RenamePreviewsToAppBuilds do
  use Ecto.Migration

  def change do
    # excellent_migrations:safety-assured-for-next-line table_renamed
    rename table(:previews), to: table(:app_builds)
  end
end
