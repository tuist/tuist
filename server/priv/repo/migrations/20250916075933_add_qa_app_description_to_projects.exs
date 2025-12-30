defmodule Tuist.Repo.Migrations.AddQaAppDescriptionToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :qa_app_description, :text, default: "", null: false
    end
  end
end
