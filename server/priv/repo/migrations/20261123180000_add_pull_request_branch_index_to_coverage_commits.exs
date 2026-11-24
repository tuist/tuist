defmodule Tuist.Repo.Migrations.AddPullRequestBranchIndexToCoverageCommits do
  @moduledoc """
  A branch's trend reads the merge checkouts its pull request runs measured
  (`Tuist.Tests.Coverage.History`), by the branch they were labelled with.
  Indexing only the pull request rows keeps that read the size of the
  branch's merge checkouts: the default branch, whose rows name no pull
  request, reads none. The SHA is included so the read is index-only: the
  planner then prefers it to the project's pull request index whatever it
  estimates a label's pull request rows to be.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index(:coverage_commits, [:project_id, :git_branch, :ran_at],
                           include: [:git_commit_sha],
                           name: :coverage_commits_project_id_git_branch_pull_request_index,
                           where: "pull_request_number > 0",
                           concurrently: true
                         )
  end
end
