defmodule Tuist.GitHistory.CompletionTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.GitHistory.Completion
  alias Tuist.GitHistory.Providers.GitHub
  alias Tuist.GitHistory.Workers.CompleteHistoryWorker
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.TestRunChangedFile
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    project =
      [vcs_connection: [repository_full_handle: "tuist/tuist"]]
      |> ProjectsFixtures.project_fixture()
      |> Repo.preload(vcs_connection: :github_app_installation)

    stub(VCS, :github_app_credentials, fn _installation -> %{} end)

    %{
      project: project,
      connection: project.vcs_connection,
      settings: GitHistory.settings(project),
      repository: GitHistory.repository_id_for_connection(project)
    }
  end

  defp commit(sha, parents, minutes) do
    %{sha: sha, parents: parents, committed_at: DateTime.add(~U[2026-09-01 00:00:00Z], minutes * 60, :second)}
  end

  test "fills the base branch, merge base, changed files and graph from the provider", %{
    project: project,
    connection: connection,
    settings: settings,
    repository: repository
  } do
    {:ok, run} =
      RunsFixtures.test_fixture(project_id: project.id, git_ref: "refs/pull/42/merge", git_commit_sha: "head")

    expect(GitHub, :pull_request, fn ^connection, 42 ->
      {:ok, %{base_branch: "main", base_sha: "basehead", head_sha: "head"}}
    end)

    expect(GitHub, :compare, fn ^connection, "main", "head", [page_budget: 20] ->
      {:ok,
       %{
         merge_base_sha: "base",
         commits: [commit("mid", ["base"], 2), commit("head", ["mid"], 3)],
         files: [%{path: "Sources/A.swift", status: "modified", git_blob_id: "blobA", hunks: [%{start: 4, end: 6}]}],
         truncated: false
       }}
    end)

    expect(GitHub, :history, fn ^connection, "base", opts ->
      assert opts[:page_budget] == 20
      {:ok, [commit("base", ["root"], 1), commit("root", [], 0)]}
    end)

    {:ok, updated} = Completion.complete(project, connection, run, settings, GitHub)

    assert {updated.base_branch, updated.merge_base_sha, updated.is_pull_request, updated.pull_request_number} ==
             {"main", "base", true, 42}

    assert {updated.git_object_format, updated.history_source, updated.history_fallback_reason} ==
             {"sha1", "provider", ""}

    {:ok, stored} = Tests.get_test(run.id)
    assert stored.merge_base_sha == "base"
    # A run that named no remote is placed in the connected repository.
    assert stored.git_repository_id == repository

    assert GitHistory.ancestors(repository, "head") == [{"head", 0}, {"mid", 1}, {"base", 2}, {"root", 3}]

    assert Tuist.ClickHouseRepo.all(
             from(f in TestRunChangedFile, where: f.test_run_id == ^run.id, select: {f.path, f.hunk_starts, f.hunk_ends})
           ) == [{"Sources/A.swift", [4], [6]}]
  end

  test "keeps what the client sent and records why the rest is missing", %{
    project: project,
    connection: connection,
    settings: settings
  } do
    {:ok, run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        git_commit_sha: "head",
        base_branch: "develop",
        history_source: "client",
        history_fallback_reason: "shallow clone",
        changed_files: [%{path: "Sources/B.swift", status: "added", hunks: [%{start: 1, end: 3}]}]
      )

    expect(GitHub, :compare, fn ^connection, "develop", "head", _opts -> {:error, "rate limited"} end)

    {:ok, updated} = Completion.complete(project, connection, run, settings, GitHub)

    assert updated.base_branch == "develop"
    assert updated.history_source == "mixed"
    assert updated.history_fallback_reason =~ "compare develop...head: rate limited"
    assert updated.history_fallback_reason =~ "no merge base to walk history from"

    assert Tuist.ClickHouseRepo.aggregate(from(f in TestRunChangedFile, where: f.test_run_id == ^run.id), :count) == 1
  end

  test "the worker skips projects with the fallback off or no connection", %{project: project} do
    {:ok, run} = RunsFixtures.test_fixture(project_id: project.id, git_commit_sha: "head")
    {:ok, project} = Tuist.Projects.update_project(project, %{git_history_provider_fallback: false})

    assert :ok = perform_job(CompleteHistoryWorker, %{"project_id" => project.id, "test_run_id" => run.id})

    unconnected = ProjectsFixtures.project_fixture()
    {:ok, other} = RunsFixtures.test_fixture(project_id: unconnected.id, git_commit_sha: "head")
    assert :ok = perform_job(CompleteHistoryWorker, %{"project_id" => unconnected.id, "test_run_id" => other.id})

    {:ok, stored} = Tests.get_test(run.id)
    assert stored.history_source == ""
  end

  test "enqueue_completion/2 only enqueues when something is missing and the fallback can run", %{
    project: project
  } do
    {:ok, complete_run} =
      RunsFixtures.test_fixture(project_id: project.id, history_source: "client", merge_base_sha: "base")

    {:ok, partial_run} = RunsFixtures.test_fixture(project_id: project.id, history_source: "client")

    assert GitHistory.enqueue_completion(project, complete_run) == :skipped
    assert {:ok, _job} = GitHistory.enqueue_completion(project, partial_run)
    assert_enqueued(worker: CompleteHistoryWorker, args: %{project_id: project.id, test_run_id: partial_run.id})

    unconnected = Repo.preload(ProjectsFixtures.project_fixture(), vcs_connection: :github_app_installation)
    assert GitHistory.enqueue_completion(unconnected, partial_run) == :skipped

    # A run from another repository than the connected one (a fork) is left alone.
    {:ok, fork_run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        history_source: "client",
        git_remote_url_origin: "https://github.com/someone/tuist-fork"
      )

    assert fork_run.git_repository_id > 0
    assert GitHistory.enqueue_completion(project, fork_run) == :skipped
  end
end
