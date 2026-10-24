defmodule Tuist.GitHistory.Workers.CompleteHistoryWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.GitHistory
  alias Tuist.GitHistory.Workers.CompleteHistoryWorker
  alias Tuist.GitHub.Client
  alias Tuist.Repo
  alias Tuist.Tests.Coverage.Workers.CommitWorker
  alias Tuist.Tests.CoverageCommit
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    stub(Environment, :github_app_configured?, fn -> true end)
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    project =
      ProjectsFixtures.project_fixture(account_id: account.id, vcs_connection: [repository_full_handle: "Acme/App"])

    repository = GitHistory.repository_id(account.id, "git@github.com:acme/app.git")
    %{account: account, project: project, repository: repository}
  end

  defp at(days_ago), do: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -days_ago * 86_400, :second)

  defp run(project, repository, attrs \\ %{}) do
    Map.merge(
      %{project_id: project.id, git_repository_id: repository, git_commit_sha: "m", git_dirty: false},
      attrs
    )
  end

  defp args(project, repository), do: %{project_id: project.id, repository_id: repository, git_commit_sha: "m"}

  describe "enqueue_completion/1" do
    test "schedules one job per repository and commit for a clean run of the connected repository", context do
      %{project: project, repository: repository} = context

      GitHistory.enqueue_completion(run(project, repository))
      GitHistory.enqueue_completion(run(project, repository))

      assert [%{scheduled_at: scheduled_at}] =
               all_enqueued(worker: CompleteHistoryWorker, args: args(project, repository))

      assert DateTime.after?(scheduled_at, DateTime.utc_now())
    end

    test "leaves out dirty runs, runs without a repository and another repository's runs", context do
      %{account: account, project: project, repository: repository} = context
      fork = GitHistory.repository_id(account.id, "https://github.com/someone/app")

      assert GitHistory.enqueue_completion(run(project, repository, %{git_dirty: true})) == :skipped
      assert GitHistory.enqueue_completion(run(project, 0)) == :skipped
      assert GitHistory.enqueue_completion(run(project, repository, %{git_commit_sha: ""})) == :skipped
      assert GitHistory.enqueue_completion(run(project, fork)) == :skipped

      refute_enqueued(worker: CompleteHistoryWorker)
    end

    test "leaves out projects without a connected repository and servers that turned the fallback off", context do
      %{account: account, repository: repository} = context
      unconnected = ProjectsFixtures.project_fixture(account_id: account.id)
      assert GitHistory.enqueue_completion(run(unconnected, repository)) == :skipped

      stub(Environment, :git_history_defaults, fn -> %{provider_fallback: false} end)
      assert GitHistory.enqueue_completion(run(context.project, repository)) == :skipped

      refute_enqueued(worker: CompleteHistoryWorker)
    end
  end

  describe "perform/1" do
    test "fills the graph through the project's installation and folds the commit's coverage again", context do
      %{project: project, repository: repository} = context
      GitHistory.record_commits(repository, "sha1", [%{sha: "m", parents: ["c"], committed_at: at(1)}])

      Repo.insert!(%CoverageCommit{
        project_id: project.id,
        git_commit_sha: "m",
        repository_id: repository,
        committed_at: DateTime.utc_now(),
        ran_at: DateTime.utc_now()
      })

      expect(Client, :list_commits, fn %{repository_full_handle: "Acme/App", sha: "c", page: 1} ->
        {:ok, [%{"sha" => "c", "parents" => [], "commit" => %{"committer" => %{"date" => DateTime.to_iso8601(at(2))}}}]}
      end)

      assert :ok = perform_job(CompleteHistoryWorker, args(project, repository))

      assert GitHistory.known?(repository, "c")
      assert_enqueued(worker: CommitWorker, args: %{project_id: project.id, git_commit_sha: "m"})
    end

    test "asks nothing and folds nothing when the graph is whole", context do
      %{project: project, repository: repository} = context
      GitHistory.record_commits(repository, "sha1", [%{sha: "m", parents: [], committed_at: at(1)}])
      reject(&Client.list_commits/1)

      assert :ok = perform_job(CompleteHistoryWorker, args(project, repository))

      refute_enqueued(worker: CommitWorker)
    end

    test "does nothing once the project's connection names another repository", context do
      %{account: account, project: project} = context
      other = GitHistory.repository_id(account.id, "https://github.com/acme/other")
      reject(&Client.list_commits/1)

      assert :ok = perform_job(CompleteHistoryWorker, %{args(project, other) | repository_id: other})
    end
  end
end
