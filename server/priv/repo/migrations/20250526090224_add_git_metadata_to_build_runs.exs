defmodule Tuist.Repo.Migrations.AddGitMetadataToBuildRuns do
  use Ecto.Migration

  def change do
    alter table(:build_runs) do
      add :git_branch, :string
      add :git_commit_sha, :string
    end
  end
end
