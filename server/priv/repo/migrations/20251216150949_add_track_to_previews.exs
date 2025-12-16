defmodule Tuist.Repo.Migrations.AddTrackToPreviews do
  use Ecto.Migration

  def change do
    alter table(:previews) do
      add :track, :string
    end

    create index(:previews, [:track])

    create unique_index(:previews, [
             :project_id,
             :bundle_identifier,
             :version,
             :git_commit_sha,
             :created_by_account_id,
             :track
           ],
           name: "previews_unique_with_track"
         )
  end
end
