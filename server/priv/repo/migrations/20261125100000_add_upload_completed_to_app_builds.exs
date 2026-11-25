defmodule Tuist.Repo.Migrations.AddUploadCompletedToAppBuilds do
  use Ecto.Migration

  # Existing builds keep counting as uploaded: nothing recorded which of them
  # finished. `tuist share` inserts new ones as not completed until
  # `multipart_complete` succeeds.
  def change do
    alter table(:app_builds) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :upload_completed, :boolean, default: true, null: false
    end
  end
end
