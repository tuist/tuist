defmodule Tuist.Repo.Migrations.CreateCoverageCommitExpectedRuns do
  @moduledoc """
  The runs a commit's pipeline started: a CI run of `tuist test` that collects
  coverage picks its run's id and registers it, with the scheme it was asked
  for, before it builds (`Tuist.Tests.Coverage.Commits.expect_runs/3`), while
  its credentials are fresh. A scheme none of whose registered runs reported
  is listed in the commit's `missing_schemes`, and its figure is a lower bound
  (`missing_scheme`).
  """
  use Ecto.Migration

  def change do
    create table(:coverage_commit_expected_runs, primary_key: false) do
      add :project_id, references(:projects, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :git_commit_sha, :string, null: false, primary_key: true
      add :test_run_id, :uuid, null: false, primary_key: true
      add :scheme, :string, null: false
      add :inserted_at, :timestamptz, null: false
    end

    alter table(:coverage_commits) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :missing_schemes, {:array, :string}, null: false, default: []
    end
  end
end
