defmodule Tuist.Repo.Migrations.AddPreviewsTable do
  use Ecto.Migration

  def change do
    create table(:previews, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, on_delete: :delete_all), required: true
      timestamps(type: :timestamptz)
    end
  end
end
