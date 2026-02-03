defmodule Cache.Repo.Migrations.RenameCasArtifactTypeToXcodeCas do
  use Ecto.Migration

  def up do
    execute "UPDATE s3_transfers SET artifact_type = 'xcode_cas' WHERE artifact_type = 'cas'"
  end

  def down do
    execute "UPDATE s3_transfers SET artifact_type = 'cas' WHERE artifact_type = 'xcode_cas'"
  end
end
