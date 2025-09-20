defmodule Tuist.Repo.Migrations.RenamePreviewsToAppBuilds do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line table_renamed
    rename table(:previews), to: table(:app_builds)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line table_renamed
    rename table(:app_builds), to: table(:previews)
  end
end
