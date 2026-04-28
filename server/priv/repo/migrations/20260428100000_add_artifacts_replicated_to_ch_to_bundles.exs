defmodule Tuist.Repo.Migrations.AddArtifactsReplicatedToChToBundles do
  use Ecto.Migration

  def change do
    alter table(:bundles) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :artifacts_replicated_to_ch, :boolean, default: false, null: false
    end
  end
end
