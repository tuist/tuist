defmodule Tuist.Repo.Migrations.AddDefaultPreviewsVisibilityToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :default_previews_visibility, :integer, default: 0, null: false
    end
  end
end
