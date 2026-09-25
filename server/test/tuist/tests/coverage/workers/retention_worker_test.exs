defmodule Tuist.Tests.Coverage.Workers.RetentionWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.GitHistory
  alias Tuist.GitHistory.Ref
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests.Coverage.Workers.RetentionWorker
  alias Tuist.Tests.CoverageCommit
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "prunes each repository's history by the widest window among its account's projects" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    narrow = ProjectsFixtures.project_fixture(account_id: account.id)
    wide = ProjectsFixtures.project_fixture(account_id: account.id)
    {:ok, _} = Projects.update_project(narrow, %{git_history_window_days: 10})
    {:ok, _} = Projects.update_project(wide, %{git_history_window_days: 30})
    repository = GitHistory.repository_id(account.id, "git@github.com:acme/app.git")

    GitHistory.record_commits(repository, "sha1", [
      %{sha: "day40", parents: [], committed_at: days_ago(40)},
      %{sha: "day20", parents: ["day40"], committed_at: days_ago(20)},
      %{sha: "today", parents: ["day20"], committed_at: DateTime.utc_now()}
    ])

    other_account = AccountsFixtures.user_fixture(preload: [:account]).account
    ProjectsFixtures.project_fixture(account_id: other_account.id)
    other_repository = GitHistory.repository_id(other_account.id, "git@github.com:acme/other.git")
    GitHistory.record_commits(other_repository, "sha1", [%{sha: "day40", parents: [], committed_at: days_ago(40)}])

    projectless_account = AccountsFixtures.user_fixture(preload: [:account]).account
    projectless_repository = GitHistory.repository_id(projectless_account.id, "git@github.com:acme/gone.git")

    GitHistory.record_commits(projectless_repository, "sha1", [
      %{sha: "day400", parents: [], committed_at: days_ago(400)},
      %{sha: "day40", parents: [], committed_at: days_ago(40)}
    ])

    assert :ok = perform_job(RetentionWorker, %{})

    assert GitHistory.missing_shas(repository, ["day40", "day20", "today"]) == ["day40"]
    # The default window (365 days) applies where no project narrows it.
    assert GitHistory.missing_shas(other_repository, ["day40"]) == []
    assert GitHistory.missing_shas(projectless_repository, ["day400", "day40"]) == ["day400"]
  end

  test "drops the commits' coverage past its retention" do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    repository = GitHistory.repository_id(account.id, "git@github.com:acme/app.git")
    main = Repo.insert!(%Ref{repository_id: repository, name: "main"})
    pull = Repo.insert!(%Ref{repository_id: repository, name: "pull/1", parent_ref_id: main.id})

    for {sha, committed_at, pull_request_number, ref} <- [
          {"expired", days_ago(1200), 0, main},
          {"kept", days_ago(10), 0, main},
          {"pull-expired", days_ago(100), 1, pull},
          {"pull-unplaced-expired", days_ago(100), 1, nil},
          {"pull-merged-kept", days_ago(100), 1, main},
          {"pull-recent-kept", days_ago(10), 1, pull}
        ] do
      Repo.insert!(%CoverageCommit{
        project_id: project.id,
        git_commit_sha: sha,
        repository_id: repository,
        ref_id: ref && ref.id,
        pull_request_number: pull_request_number,
        committed_at: committed_at,
        ran_at: committed_at,
        covered_lines: 1,
        executable_lines: 1
      })
    end

    assert :ok = perform_job(RetentionWorker, %{})

    assert from(c in CoverageCommit, where: c.project_id == ^project.id, select: c.git_commit_sha)
           |> Repo.all()
           |> Enum.sort() == ["kept", "pull-merged-kept", "pull-recent-kept"]
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)
end
