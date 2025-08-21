defmodule Tuist.Repo.Migrations.AddFileNameAndTitleToQaScreenshots do
  use Ecto.Migration

  def change do
    alter table(:qa_screenshots) do
      add :file_name, :string, null: false
      add :title, :string, null: false
    end
  end
end
