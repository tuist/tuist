defmodule Tuist.Runners.WorkflowRunsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query, only: [from: 2]
  import Mimic

  alias Tuist.Environment
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes.Identity
  alias Tuist.Runners.WorkflowRun
  alias Tuist.Runners.WorkflowRuns
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures

  # A `workflow_run.requested` delivery for a pull request from a branch of the
  # repository itself, with fields GitHub sends that the store leaves out.
  defp payload(overrides \\ %{}) do
    run =
      Map.merge(
        %{
          "id" => 30_433_642,
          "run_attempt" => 2,
          "name" => "Server",
          "event" => "pull_request",
          "head_branch" => "feature",
          "head_sha" => "acb5820ced9479c074f688cc328bf03f341a511d",
          "actor" => %{"login" => "someone"},
          "head_commit" => %{"message" => "Fix the thing", "author" => %{"email" => "someone@example.com"}},
          "head_repository" => %{"id" => 123, "full_name" => "org/repo"},
          "repository" => %{"id" => 123, "full_name" => "org/repo"},
          "pull_requests" => [
            %{
              "id" => 1,
              "number" => 7,
              "url" => "https://api.github.com/repos/org/repo/pulls/7",
              "head" => %{"ref" => "feature", "sha" => "acb5820", "repo" => %{"id" => 123, "name" => "repo"}},
              "base" => %{"ref" => "release", "sha" => "f1e2d3c", "repo" => %{"id" => 123, "name" => "repo"}}
            },
            %{"number" => 8, "head" => %{"ref" => "other"}, "base" => %{"ref" => "main"}}
          ]
        },
        overrides
      )

    %{
      "action" => "requested",
      "workflow_run" => run,
      "repository" => %{"id" => 123, "full_name" => "org/repo", "default_branch" => "main", "private" => true},
      "installation" => %{"id" => 42}
    }
  end

  defp job(account, run_id, attempt) do
    %{account_id: account.id, repository: "org/repo", workflow_run_id: run_id, run_attempt: attempt}
  end

  describe "from_webhook/1" do
    test "keeps only what a job's scope and identity read, in the API's shape" do
      assert WorkflowRuns.from_webhook(payload()) == %{
               "id" => 30_433_642,
               "run_attempt" => 2,
               "event" => "pull_request",
               "head_branch" => "feature",
               "head_repository" => %{"id" => 123},
               "pull_requests" => [
                 %{
                   "number" => 7,
                   "head" => %{"ref" => "feature", "repo" => %{"id" => 123}},
                   "base" => %{"ref" => "release", "repo" => %{"id" => 123}}
                 }
               ],
               "repository" => %{"id" => 123, "full_name" => "org/repo", "default_branch" => "main"}
             }
    end

    test "refuses a run of another repository than the delivering one" do
      assert WorkflowRuns.from_webhook(payload(%{"repository" => %{"id" => 456, "full_name" => "org/other"}})) == nil
    end

    test "refuses a run without an ID or attempt" do
      assert WorkflowRuns.from_webhook(payload(%{"run_attempt" => nil})) == nil
      assert WorkflowRuns.from_webhook(payload(%{"id" => "30433642"})) == nil
    end
  end

  describe "record/3" do
    test "stores the run for the github.com installation's account and replaces it on redelivery" do
      account = AccountsFixtures.account_fixture()

      expect(VCS, :get_github_app_installation_by_installation_id, 2, fn 42, _opts ->
        {:ok, %{account_id: account.id}}
      end)

      run = WorkflowRuns.from_webhook(payload())
      assert {:ok, _} = WorkflowRuns.record(run, 42, nil)
      assert {:ok, _} = WorkflowRuns.record(Map.put(run, "head_branch", "renamed"), 42, nil)

      assert [%WorkflowRun{run: %{"head_branch" => "renamed"}}] =
               Repo.all(from(r in WorkflowRun, where: r.account_id == ^account.id))
    end

    test "stores a GitHub Enterprise Server delivery under the account its installation row is bound to" do
      account = AccountsFixtures.account_fixture()
      reject(&VCS.get_github_app_installation_by_installation_id/2)

      assert {:ok, _} = WorkflowRuns.record(WorkflowRuns.from_webhook(payload()), 42, account.id)
      assert %{"id" => 30_433_642} = WorkflowRuns.get(account.id, 30_433_642, 2)
    end

    test "ignores installations without an account and accounts without runners" do
      account = AccountsFixtures.account_fixture()
      run = WorkflowRuns.from_webhook(payload())

      stub(VCS, :get_github_app_installation_by_installation_id, fn _, _ -> {:error, :not_found} end)
      assert {:ignored, :no_account} = WorkflowRuns.record(run, 42, nil)

      stub(Environment, :runners_available?, fn -> false end)
      assert {:ignored, :runners_disabled} = WorkflowRuns.record(run, 42, account.id)
      assert WorkflowRuns.get(account.id, 30_433_642, 2) == nil
    end
  end

  describe "Identity.github_run/1" do
    test "answers from the stored run attempt without asking GitHub" do
      account = AccountsFixtures.account_fixture()
      run = WorkflowRuns.from_webhook(payload())
      {:ok, _} = WorkflowRuns.record(run, 42, account.id)
      reject(&GitHubClient.get_workflow_run/1)
      reject(&GitHubClient.get_repository/2)

      assert {:ok, ^run} = Identity.github_run(job(account, 30_433_642, 2))
    end

    test "asks GitHub for an attempt the webhook did not report" do
      account = AccountsFixtures.account_fixture()
      {:ok, _} = WorkflowRuns.record(WorkflowRuns.from_webhook(payload()), 42, account.id)
      stub(VCS, :get_github_app_installation_for_account, fn _ -> {:ok, %{installation_id: "99"}} end)

      expect(GitHubClient, :get_workflow_run, fn %{run_id: 30_433_642} ->
        {:ok, %{"id" => 30_433_642, "run_attempt" => 1, "repository" => %{"id" => 123}}}
      end)

      expect(GitHubClient, :get_repository, fn _, "org/repo" ->
        {:ok, %{"id" => 123, "full_name" => "org/repo", "default_branch" => "main"}}
      end)

      assert {:ok, %{"run_attempt" => 1, "repository" => %{"default_branch" => "main"}}} =
               Identity.github_run(job(account, 30_433_642, 1))
    end
  end

  describe "sweep/0" do
    test "deletes runs stored more than three days ago" do
      account = AccountsFixtures.account_fixture()
      {:ok, old} = WorkflowRuns.record(WorkflowRuns.from_webhook(payload()), 42, account.id)
      {:ok, _} = WorkflowRuns.record(WorkflowRuns.from_webhook(payload(%{"run_attempt" => 3})), 42, account.id)

      Repo.update_all(from(r in WorkflowRun, where: r.id == ^old.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -73, :hour)]
      )

      assert {:ok, 1} = WorkflowRuns.sweep()
      assert WorkflowRuns.get(account.id, 30_433_642, 2) == nil
      assert %{"run_attempt" => 3} = WorkflowRuns.get(account.id, 30_433_642, 3)
    end
  end
end
