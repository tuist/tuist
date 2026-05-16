defmodule Tuist.Runners.Workers.OrphanedRunnersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.OrphanedRunnersWorker

  setup :verify_on_exit!

  defp candidate(opts) do
    %{
      workflow_job_id: Keyword.get(opts, :workflow_job_id, 76_348_428_905),
      account_id: Keyword.get(opts, :account_id, 3),
      repo: Keyword.get(opts, :repo, "tuist/tuist"),
      claimed_at: Keyword.get(opts, :claimed_at, ~U[2026-05-16 21:14:06.616167Z]),
      started_at: Keyword.get(opts, :started_at, ~U[2026-05-16 21:14:07.711527Z]),
      pod_name: Keyword.get(opts, :pod_name, "pod-1")
    }
  end

  defp account_fixture do
    TuistTestSupport.Fixtures.AccountsFixtures.organization_fixture(name: "tuist-#{System.unique_integer([:positive])}").account
  end

  describe "perform/1" do
    test "re-queues + releases when GitHub still reports the workflow_job as queued" do
      # The exact case shard 0 hit on 2026-05-16: PG/CH said the
      # workflow_job was claimed and running, but the Pod's container
      # never started so GH never saw a registered runner. The
      # worker re-queues + releases so another Pod can pick up.
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :list_orphaned_running, fn _threshold -> [orphan] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn id ->
        assert id == account.id
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _installation, "tuist/tuist", wfid ->
        assert wfid == orphan.workflow_job_id
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      expect(Jobs, :record_queued, fn wfid ->
        assert wfid == orphan.workflow_job_id
        :ok
      end)

      expect(Claims, :release, fn wfid, handle ->
        assert wfid == orphan.workflow_job_id
        assert handle == orphan.claimed_at
        :ok
      end)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "leaves real running builds alone when GitHub reports in_progress" do
      # The runner registered fine and is actually executing the
      # workflow_job. Nothing to recover; reaping here would kill a
      # live build.
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :list_orphaned_running, fn _ -> [orphan] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "in_progress", conclusion: nil, runner_name: "runner-x"}}
      end)

      reject(&Jobs.record_queued/1)
      reject(&Claims.release/2)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "no-op when GitHub reports completed — webhook redelivery handles those" do
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :list_orphaned_running, fn _ -> [orphan] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "completed", conclusion: "success", runner_name: "runner-x"}}
      end)

      reject(&Jobs.record_queued/1)
      reject(&Claims.release/2)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "skips on transient GitHub lookup failure" do
      # 502 / network blip / rate limit — retry next tick rather
      # than re-queue speculatively. We don't have proof the runner
      # is dead without a fresh GH status.
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :list_orphaned_running, fn _ -> [orphan] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:error, {:http, 502, "bad gateway"}}
      end)

      reject(&Jobs.record_queued/1)
      reject(&Claims.release/2)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "is a no-op when nothing is orphaned" do
      expect(Jobs, :list_orphaned_running, fn _ -> [] end)

      reject(&Tuist.VCS.get_github_app_installation_for_account/1)
      reject(&GitHubClient.get_workflow_job/3)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end
  end
end
