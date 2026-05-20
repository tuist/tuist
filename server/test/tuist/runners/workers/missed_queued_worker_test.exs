defmodule Tuist.Runners.Workers.MissedQueuedWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Accounts
  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.MissedQueuedWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  defp enabled_account(cap \\ 5) do
    account =
      AccountsFixtures.organization_fixture(name: "tuist-#{System.unique_integer([:positive])}").account

    account
    |> Ecto.Changeset.change(runner_max_concurrent: cap)
    |> Tuist.Repo.update!()
  end

  defp gh_job(opts \\ []) do
    %{
      id: Keyword.get(opts, :id, 999_111_222),
      run_id: Keyword.get(opts, :run_id, 555_666_777),
      run_attempt: Keyword.get(opts, :run_attempt, 1),
      name: Keyword.get(opts, :name, "build"),
      status: Keyword.get(opts, :status, "queued"),
      labels: Keyword.get(opts, :labels, ["self-hosted", "tuist-mac"]),
      head_branch: Keyword.get(opts, :head_branch, "main"),
      head_sha: Keyword.get(opts, :head_sha, "abc123"),
      created_at: Keyword.get(opts, :created_at, DateTime.add(DateTime.utc_now(), -120, :second))
    }
  end

  describe "perform/1" do
    test "is a no-op when no accounts have runners enabled" do
      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [] end)

      reject(&Tuist.VCS.get_github_app_installation_for_account/1)
      reject(&GitHubClient.list_installation_repositories/2)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})
    end

    test "enqueues the missing workflow_job when GitHub has a queued job we don't know about" do
      account = enabled_account()
      job = gh_job()

      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [account] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn id ->
        assert id == account.id
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :list_installation_repositories, fn _installation, _opts ->
        {:ok,
         %{
           meta: %{next_url: nil},
           repositories: [%{id: 1, name: "app", full_name: "tuist/app", private: false, default_branch: "main"}]
         }}
      end)

      expect(GitHubClient, :list_queued_workflow_runs, fn _installation, "tuist/app", opts ->
        assert match?(%DateTime{}, Keyword.get(opts, :created_after))
        {:ok, [%{id: job.run_id, name: "CI", head_branch: "main", head_sha: "abc123", run_attempt: 1}]}
      end)

      expect(GitHubClient, :list_workflow_run_jobs, fn _installation, "tuist/app", run_id ->
        assert run_id == job.run_id
        {:ok, [job]}
      end)

      expect(Dispatch, :match_pool, fn labels ->
        assert labels == job.labels
        {:ok, %{name: "default", dispatch_label: "tuist-mac", runner_labels: ["self-hosted", "macOS", "ARM64"]}}
      end)

      expect(Jobs, :exists?, fn id ->
        assert id == job.id
        false
      end)

      expect(Jobs, :enqueue, fn attrs ->
        assert attrs.workflow_job_id == job.id
        assert attrs.account_id == account.id
        assert attrs.fleet_name == "default"
        assert attrs.repo == "tuist/app"
        assert attrs.workflow_run_id == job.run_id
        assert attrs.job_name == job.name
        assert attrs.head_branch == job.head_branch
        assert attrs.head_sha == job.head_sha
        :ok
      end)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})
    end

    test "skips workflow_jobs we already have in ClickHouse (late webhook arrived first)" do
      # The dedup gate that keeps the recovery path idempotent
      # against a webhook landing between our list-jobs call and
      # our enqueue call.
      account = enabled_account()
      job = gh_job()

      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [account] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :list_installation_repositories, fn _installation, _opts ->
        {:ok,
         %{
           meta: %{next_url: nil},
           repositories: [%{id: 1, name: "app", full_name: "tuist/app", private: false, default_branch: "main"}]
         }}
      end)

      expect(GitHubClient, :list_queued_workflow_runs, fn _i, "tuist/app", _opts ->
        {:ok, [%{id: job.run_id, name: "CI", head_branch: "main", head_sha: "abc123", run_attempt: 1}]}
      end)

      expect(GitHubClient, :list_workflow_run_jobs, fn _i, "tuist/app", _run_id ->
        {:ok, [job]}
      end)

      expect(Dispatch, :match_pool, fn _labels ->
        {:ok, %{name: "default", dispatch_label: "tuist-mac", runner_labels: []}}
      end)

      expect(Jobs, :exists?, fn _id -> true end)
      reject(&Jobs.enqueue/1)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})
    end

    test "skips workflow_jobs whose labels do not match any pool" do
      # `runs-on: ubuntu-latest` or another provider's label.
      # Recovery is only for our own queued jobs.
      account = enabled_account()
      job = gh_job(labels: ["ubuntu-latest"])

      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [account] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :list_installation_repositories, fn _i, _opts ->
        {:ok,
         %{
           meta: %{next_url: nil},
           repositories: [%{id: 1, name: "app", full_name: "tuist/app", private: false, default_branch: "main"}]
         }}
      end)

      expect(GitHubClient, :list_queued_workflow_runs, fn _i, _r, _opts ->
        {:ok, [%{id: job.run_id, name: "", head_branch: "", head_sha: "", run_attempt: 1}]}
      end)

      expect(GitHubClient, :list_workflow_run_jobs, fn _i, _r, _id -> {:ok, [job]} end)

      expect(Dispatch, :match_pool, fn _labels -> {:error, :no_matching_pool} end)

      reject(&Jobs.exists?/1)
      reject(&Jobs.enqueue/1)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})
    end

    test "skips workflow_jobs queued for less than the minimum age (let the normal webhook path land first)" do
      # Without this gate, the worker races every legitimately-
      # delivered webhook — a job that GitHub fired into our endpoint
      # 2s ago is still in flight through DispatchWorker and would
      # look "missed" to us.
      account = enabled_account()
      fresh_job = gh_job(created_at: DateTime.add(DateTime.utc_now(), -5, :second))

      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [account] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :list_installation_repositories, fn _i, _opts ->
        {:ok,
         %{
           meta: %{next_url: nil},
           repositories: [%{id: 1, name: "app", full_name: "tuist/app", private: false, default_branch: "main"}]
         }}
      end)

      expect(GitHubClient, :list_queued_workflow_runs, fn _i, _r, _opts ->
        {:ok, [%{id: fresh_job.run_id, name: "", head_branch: "", head_sha: "", run_attempt: 1}]}
      end)

      expect(GitHubClient, :list_workflow_run_jobs, fn _i, _r, _id -> {:ok, [fresh_job]} end)

      reject(&Dispatch.match_pool/1)
      reject(&Jobs.exists?/1)
      reject(&Jobs.enqueue/1)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})
    end

    test "skips jobs not in queued state (already claimed / running / completed)" do
      account = enabled_account()
      running = gh_job(status: "in_progress")

      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [account] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :list_installation_repositories, fn _i, _opts ->
        {:ok,
         %{
           meta: %{next_url: nil},
           repositories: [%{id: 1, name: "app", full_name: "tuist/app", private: false, default_branch: "main"}]
         }}
      end)

      expect(GitHubClient, :list_queued_workflow_runs, fn _i, _r, _opts ->
        {:ok, [%{id: running.run_id, name: "", head_branch: "", head_sha: "", run_attempt: 1}]}
      end)

      expect(GitHubClient, :list_workflow_run_jobs, fn _i, _r, _id -> {:ok, [running]} end)

      reject(&Dispatch.match_pool/1)
      reject(&Jobs.exists?/1)
      reject(&Jobs.enqueue/1)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})
    end

    test "paginates through the installation's repositories" do
      account = enabled_account()
      job = gh_job()

      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [account] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :list_installation_repositories, 2, fn _i, opts ->
        if Keyword.has_key?(opts, :next_url) do
          {:ok,
           %{
             meta: %{next_url: nil},
             repositories: [
               %{id: 2, name: "b", full_name: "tuist/b", private: false, default_branch: "main"}
             ]
           }}
        else
          {:ok,
           %{
             meta: %{next_url: "https://api.github.com/installation/repositories?page=2"},
             repositories: [
               %{id: 1, name: "a", full_name: "tuist/a", private: false, default_branch: "main"}
             ]
           }}
        end
      end)

      # Both repos get listed for queued runs. Only "tuist/b" has one.
      expect(GitHubClient, :list_queued_workflow_runs, 2, fn
        _i, "tuist/a", _opts ->
          {:ok, []}

        _i, "tuist/b", _opts ->
          {:ok, [%{id: job.run_id, name: "", head_branch: "", head_sha: "", run_attempt: 1}]}
      end)

      expect(GitHubClient, :list_workflow_run_jobs, fn _i, "tuist/b", _id -> {:ok, [job]} end)

      expect(Dispatch, :match_pool, fn _labels ->
        {:ok, %{name: "default", dispatch_label: "tuist-mac", runner_labels: []}}
      end)

      expect(Jobs, :exists?, fn _ -> false end)

      expect(Jobs, :enqueue, fn attrs ->
        assert attrs.repo == "tuist/b"
        :ok
      end)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})
    end

    test "continues iterating other accounts when one account's GitHub lookup fails" do
      # Per-account isolation: a customer's installation being
      # revoked / suspended / rate-limited must not stall recovery
      # for everyone else.
      account_a = enabled_account()
      account_b = enabled_account()
      job = gh_job()

      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [account_a, account_b] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, 2, fn
        id when id == account_a.id ->
          {:error, :not_found}

        id when id == account_b.id ->
          {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :list_installation_repositories, fn _i, _opts ->
        {:ok,
         %{
           meta: %{next_url: nil},
           repositories: [%{id: 1, name: "x", full_name: "tuist/x", private: false, default_branch: "main"}]
         }}
      end)

      expect(GitHubClient, :list_queued_workflow_runs, fn _i, _r, _opts ->
        {:ok, [%{id: job.run_id, name: "", head_branch: "", head_sha: "", run_attempt: 1}]}
      end)

      expect(GitHubClient, :list_workflow_run_jobs, fn _i, _r, _id -> {:ok, [job]} end)

      expect(Dispatch, :match_pool, fn _ ->
        {:ok, %{name: "default", dispatch_label: "tuist-mac", runner_labels: []}}
      end)

      expect(Jobs, :exists?, fn _ -> false end)
      expect(Jobs, :enqueue, fn _ -> :ok end)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})
    end

    test "continues iterating other repos when one repo's list-runs call fails (transient API error)" do
      account = enabled_account()
      job = gh_job()

      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [account] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :list_installation_repositories, fn _i, _opts ->
        {:ok,
         %{
           meta: %{next_url: nil},
           repositories: [
             %{id: 1, name: "a", full_name: "tuist/a", private: false, default_branch: "main"},
             %{id: 2, name: "b", full_name: "tuist/b", private: false, default_branch: "main"}
           ]
         }}
      end)

      expect(GitHubClient, :list_queued_workflow_runs, 2, fn
        _i, "tuist/a", _opts ->
          {:error, {:http, 502, "bad gateway"}}

        _i, "tuist/b", _opts ->
          {:ok, [%{id: job.run_id, name: "", head_branch: "", head_sha: "", run_attempt: 1}]}
      end)

      expect(GitHubClient, :list_workflow_run_jobs, fn _i, "tuist/b", _id -> {:ok, [job]} end)

      expect(Dispatch, :match_pool, fn _ ->
        {:ok, %{name: "default", dispatch_label: "tuist-mac", runner_labels: []}}
      end)

      expect(Jobs, :exists?, fn _ -> false end)
      expect(Jobs, :enqueue, fn _ -> :ok end)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})
    end

    test "emits recovery telemetry with kind=missed_queued" do
      account = enabled_account()
      job = gh_job()

      :telemetry.attach(
        "missed-queued-test",
        Tuist.Runners.Telemetry.event_name_recovery(),
        fn _event, measurements, metadata, _ ->
          send(self(), {:recovery, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("missed-queued-test") end)

      expect(Accounts, :list_accounts_with_runners_enabled, fn -> [account] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 42, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :list_installation_repositories, fn _i, _opts ->
        {:ok,
         %{
           meta: %{next_url: nil},
           repositories: [%{id: 1, name: "x", full_name: "tuist/x", private: false, default_branch: "main"}]
         }}
      end)

      expect(GitHubClient, :list_queued_workflow_runs, fn _i, _r, _opts ->
        {:ok, [%{id: job.run_id, name: "", head_branch: "", head_sha: "", run_attempt: 1}]}
      end)

      expect(GitHubClient, :list_workflow_run_jobs, fn _i, _r, _id -> {:ok, [job]} end)

      expect(Dispatch, :match_pool, fn _ ->
        {:ok, %{name: "default", dispatch_label: "tuist-mac", runner_labels: []}}
      end)

      expect(Jobs, :exists?, fn _ -> false end)
      expect(Jobs, :enqueue, fn _ -> :ok end)

      assert :ok = MissedQueuedWorker.perform(%Oban.Job{})

      assert_received {:recovery, %{count: 1}, %{kind: "missed_queued"}}
    end
  end

  describe "list_accounts_with_runners_enabled integration" do
    # Light integration test against the real Accounts function, so
    # a schema rename on `runner_max_concurrent` doesn't silently
    # break the worker's input.
    test "returns only accounts with runner_max_concurrent > 0" do
      disabled =
        AccountsFixtures.organization_fixture(name: "disabled-#{System.unique_integer([:positive])}").account

      enabled = enabled_account(3)

      ids = Enum.map(Accounts.list_accounts_with_runners_enabled(), & &1.id)

      assert enabled.id in ids
      refute disabled.id in ids
    end
  end
end
