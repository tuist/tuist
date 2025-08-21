defmodule Tuist.Repo.Migrations.AddS3UrlToQaScreenshots do
  use Ecto.Migration

  def change do
    alter table(:qa_screenshots) do
      add :s3_url, :string, null: false
    end
  end
end
