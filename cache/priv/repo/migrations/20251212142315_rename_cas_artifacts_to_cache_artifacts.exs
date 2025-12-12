defmodule Cache.Repo.Migrations.RenameCasArtifactsToCacheArtifacts do
  use Ecto.Migration

  def change do
    rename table(:cas_artifacts), to: table(:cache_artifacts)
  end
end
