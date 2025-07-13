defmodule Tuist.Repo.Migrations.DropArtifactsForeignKey do
  use Ecto.Migration

  def change do
    drop constraint(:artifacts, "artifacts_artifact_id_fkey")
  end
end
