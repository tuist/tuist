defmodule Tuist.ClickHouseRepo.Migrations.DropLegacyArtifactPathColumn do
  use Ecto.Migration

  def up do
    alter table(:command_events) do
      remove :legacy_artifact_path
    end
  end

  def down do
    alter table(:command_events) do
      add :legacy_artifact_path, :boolean, default: false
    end
  end
end
