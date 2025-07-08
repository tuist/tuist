defmodule Tuist.Repo.Migrations.AddPreviewIdToAppBuilds do
  use Ecto.Migration

  def change do
    alter table(:app_builds) do
      add :preview_id, references(:previews, type: :uuid, on_delete: :delete_all)
    end
  end
end
