defmodule Tuist.Repo.Migrations.CreateCoverageCommitCompletions do
  @moduledoc """
  Completion signals (`tuist coverage complete`) for commits no run has
  folded yet: the signal usually lands before the runs' coverage is
  processed, and the commit's first fold applies it
  (`Tuist.Tests.Coverage.Commits.signal_complete/2`).
  """
  use Ecto.Migration

  def change do
    create table(:coverage_commit_completions, primary_key: false) do
      add :project_id, references(:projects, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :git_commit_sha, :string, null: false, primary_key: true
      add :inserted_at, :timestamptz, null: false
    end
  end
end
