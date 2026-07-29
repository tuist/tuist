defmodule Tuist.Runners.Workers.StaleQueuedJobsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.StaleQueuedJobsWorker

  setup :verify_on_exit!

  defp candidate(opts) do
    %{
      workflow_job_id: Keyword.get(opts, :workflow_job_id, 76_348_428_905),
      account_id: Keyword.get(opts, :account_id, 3),
      repository: Keyword.get(opts, :repository, "tuist/tuist"),
      # Default: queued long enough to verify against GitHub (> 1h) but
      # within the 24h hard backstop, so backstop reaps don't fire
      # unless a test explicitly ages the row.
      enqueued_at: Keyword.get(opts, :enqueued_at, DateTime.add(DateTime.utc_now(), -2, :hour))
    }
  end

  defp account_fixture do
    TuistTestSupport.Fixtures.AccountsFixtures.organization_fixture(name: "tuist-#{System.unique_integer([:positive])}").account
  end

  describe "perform/1" do
    test "reconciles a queued row when GitHub reports the workflow_job completed" do
      # We accepted the queue webhook but never saw the matching
      # completed delivery (lost past the redelivery window). GitHub's
      # terminal status is the source of truth — mark it completed with
      # GitHub's conclusion so it leaves the queue.
      account = account_fixture()
      stale = candidate(account_id: account.id)

      expect(Jobs, :list_stale_queued, fn _floor, _before -> [stale] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn id ->
        assert id == account.id
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _installation, "tuist/tuist", wfid ->
        assert wfid == stale.workflow_job_id
        {:ok, %{status: "completed", conclusion: "success", runner_name: nil}}
      end)

      expect(Claims, :complete, fn wfid ->
        assert wfid == stale.workflow_job_id
        :ok
      end)

      expect(Jobs, :complete, fn wfid, conclusion ->
        assert wfid == stale.workflow_job_id
        assert conclusion == "success"
        {:ok, %{}}
      end)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end

    test "completes a queued row when GitHub returns 404 (workflow_job pruned)" do
      # GitHub pruned the job (cancelled + retention, or the run was
      # superseded). It can't be live; complete it so it leaves the
      # queue with an empty conclusion.
      account = account_fixture()
      stale = candidate(account_id: account.id)

      expect(Jobs, :list_stale_queued, fn _floor, _before -> [stale] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid -> {:error, :not_found} end)

      expect(Claims, :complete, fn _wfid -> :ok end)
      expect(Jobs, :complete, fn _wfid, "" -> {:ok, %{}} end)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end

    test "leaves a still-queued job within the backstop alone" do
      # GitHub agrees it's still queued and it's only 2h old — a runner
      # could still pick it up (account at cap, pool scaling). Reaping
      # here would kill a legitimately-pending job.
      account = account_fixture()
      stale = candidate(account_id: account.id)

      expect(Jobs, :list_stale_queued, fn _floor, _before -> [stale] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      reject(&Jobs.complete/2)
      reject(&Claims.complete/1)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end

    test "force-completes a still-queued job past the hard backstop as stale" do
      # The screenshot case: queued 28 days, GitHub still reports
      # queued. No runner will ever pick it up; force-complete with the
      # synthetic `stale` conclusion so it can't sit forever.
      account = account_fixture()
      stale = candidate(account_id: account.id, enqueued_at: DateTime.add(DateTime.utc_now(), -28, :day))

      expect(Jobs, :list_stale_queued, fn _floor, _before -> [stale] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      expect(Claims, :complete, fn _wfid -> :ok end)

      expect(Jobs, :complete, fn wfid, conclusion ->
        assert wfid == stale.workflow_job_id
        assert conclusion == "stale"
        {:ok, %{}}
      end)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end

    test "never force-completes a job GitHub reports as in_progress, even past the backstop" do
      # A runner accepted the job outside our dispatch flow. It's live
      # and will fire completed within GitHub's per-job execution
      # limit; reaping it would terminate a real build.
      account = account_fixture()
      stale = candidate(account_id: account.id, enqueued_at: DateTime.add(DateTime.utc_now(), -28, :day))

      expect(Jobs, :list_stale_queued, fn _floor, _before -> [stale] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "in_progress", conclusion: nil, runner_name: "runner-x"}}
      end)

      reject(&Jobs.complete/2)
      reject(&Claims.complete/1)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end

    test "reaps past the backstop when the GitHub lookup fails" do
      # GitHub is unreachable, but a 28-day-old queued row is
      # definitively dead — the backstop must not depend on a working
      # GitHub API or the row would survive forever.
      account = account_fixture()
      stale = candidate(account_id: account.id, enqueued_at: DateTime.add(DateTime.utc_now(), -28, :day))

      expect(Jobs, :list_stale_queued, fn _floor, _before -> [stale] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid -> {:error, {:http, 502, "bad gateway"}} end)

      expect(Claims, :complete, fn _wfid -> :ok end)
      expect(Jobs, :complete, fn _wfid, "stale" -> {:ok, %{}} end)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end

    test "leaves a within-backstop job alone when the GitHub lookup fails" do
      # Can't prove the job is dead and it's only 2h old — retry next
      # tick rather than reap speculatively.
      account = account_fixture()
      stale = candidate(account_id: account.id)

      expect(Jobs, :list_stale_queued, fn _floor, _before -> [stale] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid -> {:error, {:http, 502, "bad gateway"}} end)

      reject(&Jobs.complete/2)
      reject(&Claims.complete/1)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end

    test "reaps a row with no repository past the backstop without calling GitHub" do
      # Legacy pre-profiles rows can carry an empty repository, which
      # can't address the Actions jobs API. Only the backstop can
      # resolve them; we skip the GitHub round-trip entirely.
      stale = candidate(repository: "", enqueued_at: DateTime.add(DateTime.utc_now(), -28, :day))

      expect(Jobs, :list_stale_queued, fn _floor, _before -> [stale] end)

      reject(&Tuist.VCS.get_github_app_installation_for_account/1)
      reject(&GitHubClient.get_workflow_job/3)

      expect(Claims, :complete, fn _wfid -> :ok end)
      expect(Jobs, :complete, fn _wfid, "stale" -> {:ok, %{}} end)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end

    test "leaves a within-backstop row with no repository alone" do
      stale = candidate(repository: "")

      expect(Jobs, :list_stale_queued, fn _floor, _before -> [stale] end)

      reject(&Tuist.VCS.get_github_app_installation_for_account/1)
      reject(&GitHubClient.get_workflow_job/3)
      reject(&Jobs.complete/2)
      reject(&Claims.complete/1)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end

    test "is a no-op when nothing is stale-queued" do
      expect(Jobs, :list_stale_queued, fn _floor, _before -> [] end)

      reject(&Tuist.VCS.get_github_app_installation_for_account/1)
      reject(&GitHubClient.get_workflow_job/3)

      assert :ok = StaleQueuedJobsWorker.perform(%Oban.Job{})
    end
  end
end
