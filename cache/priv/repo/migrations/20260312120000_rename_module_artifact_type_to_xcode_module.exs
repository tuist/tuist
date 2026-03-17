defmodule Cache.Repo.Migrations.RenameModuleArtifactTypeToXcodeModule do
  use Ecto.Migration

  def up do
    execute("UPDATE s3_transfers SET artifact_type = 'xcode_module' WHERE artifact_type = 'module'")
  end

  def down do
    execute("UPDATE s3_transfers SET artifact_type = 'module' WHERE artifact_type = 'xcode_module'")
  end
end
