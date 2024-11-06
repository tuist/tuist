defmodule Tuist.Repo.Migrations.AddCommandEventProjectIdNameGitCommitShaIndex do
  use Ecto.Migration

  def change do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:command_events, [:name, :project_id, :git_commit_sha])
  end
end
