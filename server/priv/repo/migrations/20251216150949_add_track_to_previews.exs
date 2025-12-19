defmodule Tuist.Repo.Migrations.AddTrackToPreviews do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      add :track, :citext, default: "", null: false
    end

    create index(:previews, [:track])
  end
end
