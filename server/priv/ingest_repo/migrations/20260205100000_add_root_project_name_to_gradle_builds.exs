defmodule Tuist.IngestRepo.Migrations.AddRootProjectNameToGradleBuilds do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE gradle_builds ADD COLUMN root_project_name Nullable(String) AFTER git_ref",
      "ALTER TABLE gradle_builds DROP COLUMN root_project_name"
    )
  end
end
