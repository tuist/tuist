defmodule Tuist.Repo.Migrations.AddGitMetadataToCommandEvents do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add :git_commit_sha, :string, null: true
      add :git_remote_url_origin, :string, null: true
      add :git_ref, :string, null: true
    end
  end
end
