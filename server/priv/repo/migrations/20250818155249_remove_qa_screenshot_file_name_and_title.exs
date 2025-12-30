defmodule Tuist.Repo.Migrations.RemoveQaScreenshotFileNameAndTitle do
  use Ecto.Migration

  def up do
    alter table(:qa_screenshots) do
      remove :file_name, :string
      remove :title, :string
    end
  end

  def down do
    alter table(:qa_screenshots) do
      add :file_name, :string
      add :title, :string
    end
  end
end
