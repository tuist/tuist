defmodule Tuist.IngestRepo.Migrations.AddCustomMetadataToGradleBuilds do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE gradle_builds ADD COLUMN IF NOT EXISTS custom_tags Array(String) DEFAULT []"
    )

    execute(
      "ALTER TABLE gradle_builds ADD COLUMN IF NOT EXISTS custom_values Map(String, String) DEFAULT map()"
    )
  end

  def down do
    execute("ALTER TABLE gradle_builds DROP COLUMN IF EXISTS custom_tags")
    execute("ALTER TABLE gradle_builds DROP COLUMN IF EXISTS custom_values")
  end
end
