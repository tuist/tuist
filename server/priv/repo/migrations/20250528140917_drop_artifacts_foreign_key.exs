defmodule Tuist.Repo.Migrations.DropArtifactsForeignKey do
  use Ecto.Migration

  def up do
    drop constraint(:artifacts, "artifacts_artifact_id_fkey")
  end

  def down do
    alter table(:artifacts) do
      modify :artifact_id, references(:artifacts, type: :uuid, on_delete: :delete_all)
    end
  end
end
