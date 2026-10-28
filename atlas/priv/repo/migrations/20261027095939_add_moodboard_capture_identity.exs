defmodule Atlas.Repo.Migrations.AddMoodboardCaptureIdentity do
  use Ecto.Migration

  def change do
    alter table(:moodboard_resources) do
      add :capture_id, :uuid
      add :capture_hash, :string
    end

    create unique_index(:moodboard_resources, [:created_by_id, :capture_id])
  end
end
