defmodule Tuist.Repo.Migrations.AddPreviewReleaseNotes do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      add :release_notes, :text
    end
  end
end
