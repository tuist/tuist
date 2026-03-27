defmodule Cache.Repo.Migrations.RenameCasArtifactTypeToXcodeCache do
  use Ecto.Migration

  def up do
    execute("UPDATE s3_transfers SET artifact_type = 'xcode_cache' WHERE artifact_type = 'cas'")
  end

  def down do
    execute("UPDATE s3_transfers SET artifact_type = 'cas' WHERE artifact_type = 'xcode_cache'")
  end
end
