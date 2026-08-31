defmodule Tuist.IngestRepo.Migrations.AddCustomMetadataToGradleBuilds do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE gradle_builds ADD COLUMN custom_tags Array(String) DEFAULT []")

    execute(
      "ALTER TABLE gradle_builds ADD COLUMN custom_values Map(String, String) DEFAULT map()"
    )
  end

  def down do
    execute("ALTER TABLE gradle_builds DROP COLUMN custom_tags")
    execute("ALTER TABLE gradle_builds DROP COLUMN custom_values")
  end
end
