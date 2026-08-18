defmodule Tuist.Runners.Workers.OrphanedRunnersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.Workers.OrphanedRunnersWorker

  setup :verify_on_exit!

  defp candidate(opts) do
    %{
      workflow_job_id: Keyword.get(opts, :workflow_job_id, 76_348_428_905),
      account_id: Keyword.get(opts, :account_id, 3),
      repository: Keyword.get(opts, :repository, "tuist/tuist"),
      claimed_at: Keyword.get(opts, :claimed_at, ~U[2026-05-16 21:14:06.616167Z]),
      started_at: Keyword.get(opts, :started_at, ~U[2026-05-16 21:14:07.711527Z]),
      pod_name: Keyword.get(opts, :pod_name, "pod-1"),
      fleet_name: Keyword.get(opts, :fleet_name, "tuist-tuist-runner-pool-macos-26-6")
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

    test "recovery telemetry carries the fleet and how long the job sat stranded" do
      # A stranded job is invisible to every queue signal: its row is
      # `running`, so queue depth and queue age both read zero while the
      # customer watches "waiting for a runner". Recovery is the only
      # point that knows, via the GitHub cross-check, that the wait was
      # real — so it has to carry both which pool stranded and how long
      # the customer actually waited.
      account = account_fixture()

      orphan =
        candidate(
          account_id: account.id,
          fleet_name: "tuist-tuist-runner-pool-macos-26-6",
          started_at: DateTime.add(DateTime.utc_now(), -90, :second)
        )

      expect(Jobs, :list_orphaned_running, fn _threshold -> [orphan] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      expect(Jobs, :record_queued, fn _wfid -> :ok end)
      expect(Claims, :release, fn _wfid, _handle -> :ok end)

      # Every recovery worker emits this event and telemetry handlers are
      # VM-global, so `:telemetry_test.attach_event_handlers/2` would forward
      # a sibling `async: true` module's emission into this mailbox and it
      # would win the `assert_receive`. The handler runs in the emitting
      # process, so pinning it to ours keeps only the event this test caused.
      handler_id = make_ref()
      test_pid = self()
      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok =
        :telemetry.attach(
          handler_id,
          Telemetry.event_name_recovery(),
          fn _name, measurements, metadata, _config ->
            if self() == test_pid do
              send(test_pid, {:recovery, handler_id, measurements, metadata})
            end
          end,
          nil
        )

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})

      assert_receive {:recovery, ^handler_id, measurements, metadata}
      assert metadata.kind == "orphan_requeued"
      assert metadata.fleet == "tuist-tuist-runner-pool-macos-26-6"
      assert_in_delta measurements.stranded_ms, 90_000, 5_000
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

    test "frees the claim when GitHub reports completed but we missed the webhook" do
      # Webhook delivery can be dropped (GitHub retries exhaust, our
      # endpoint 5xx'd, etc.). Without this branch, the PG claim
      # would stay in lifecycle_state='running' forever — the
      # StaleClaimsWorker excludes running, and this worker would
      # see the same row every minute. Since the GH lookup proves
      # the job is no longer live, free the cap slot ourselves.
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :list_orphaned_running, fn _ -> [orphan] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "completed", conclusion: "success", runner_name: "runner-x"}}
      end)

      expect(Claims, :complete, fn wfid ->
        assert wfid == orphan.workflow_job_id
        :ok
      end)

      expect(Jobs, :complete, fn wfid, conclusion ->
        assert wfid == orphan.workflow_job_id
        assert conclusion == "success"
        {:ok, %{}}
      end)

      reject(&Jobs.record_queued/1)
      reject(&Claims.release/2)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "frees the claim when GitHub returns 404 (workflow_job pruned past retention)" do
      # GitHub retains workflow_jobs for 90 days. If our PG claim
      # outlives that window (catastrophic outage), the GET returns
      # 404. The job cannot be live; treat as completed so we don't
      # leak the cap slot.
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :list_orphaned_running, fn _ -> [orphan] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:error, :not_found}
      end)

      expect(Claims, :complete, fn wfid ->
        assert wfid == orphan.workflow_job_id
        :ok
      end)

      expect(Jobs, :complete, fn _wfid, "" -> {:ok, %{}} end)

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

  describe "perform/1 with a targeted workflow_job_id" do
    test "recovers the named job without waiting out the staleness floor" do
      # The controller reported the Pod stopped seconds ago, so the row
      # is far too young for the sweep. The evidence the sweep is
      # waiting for — that the Pod is gone — is already in hand, and
      # until the row leaves `running` the job is invisible to dispatch.
      account = account_fixture()
      orphan = candidate(account_id: account.id, started_at: DateTime.utc_now())

      reject(&Jobs.list_orphaned_running/1)

      expect(Jobs, :get_orphaned_running, fn wfid ->
        assert wfid == orphan.workflow_job_id
        Map.delete(orphan, :status)
      end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      expect(Jobs, :record_queued, fn wfid ->
        assert wfid == orphan.workflow_job_id
        :ok
      end)

      expect(Claims, :release, fn _wfid, _handle -> :ok end)

      assert :ok =
               OrphanedRunnersWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => orphan.workflow_job_id, "pod_name" => orphan.pod_name}
               })
    end

    test "still defers to GitHub before re-queueing" do
      # Skipping the age gate must not skip the cross-check. A Pod can
      # stop holding a claim for a job GitHub already handed to another
      # runner and watched complete.
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :get_orphaned_running, fn _wfid -> Map.delete(orphan, :status) end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "in_progress", conclusion: nil, runner_name: "runner-x"}}
      end)

      reject(&Jobs.record_queued/1)
      reject(&Claims.release/2)

      assert :ok =
               OrphanedRunnersWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => orphan.workflow_job_id, "pod_name" => orphan.pod_name}
               })
    end

    test "leaves a replacement attempt alone when the job was re-claimed before this ran" do
      # The targeted run can be delayed long enough for the job to be
      # re-queued and picked up by a fresh Pod. Acting on the row then
      # would release the REPLACEMENT's claim using the replacement's own
      # `claimed_at` (GitHub still reports `queued` while its runner
      # registers), killing a live attempt. The stale-claim handle guard
      # in `Claims.release/2` cannot catch it, because re-reading the row
      # hands us the new handle rather than the old one.
      account = account_fixture()

      replacement =
        candidate(
          account_id: account.id,
          pod_name: "pod-replacement",
          claimed_at: DateTime.utc_now()
        )

      expect(Jobs, :get_orphaned_running, fn _wfid -> Map.delete(replacement, :status) end)

      reject(&Tuist.VCS.get_github_app_installation_for_account/1)
      reject(&GitHubClient.get_workflow_job/3)
      reject(&Jobs.record_queued/1)
      reject(&Claims.release/2)

      assert :ok =
               OrphanedRunnersWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => replacement.workflow_job_id, "pod_name" => "pod-that-stopped"}
               })
    end

    test "is a no-op when the job already left the running state" do
      # The executor's `completed` webhook landed, or another Pod
      # re-claimed the job, between the release and this run.
      expect(Jobs, :get_orphaned_running, fn _wfid -> nil end)

      reject(&Tuist.VCS.get_github_app_installation_for_account/1)
      reject(&GitHubClient.get_workflow_job/3)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{args: %{"workflow_job_id" => 42, "pod_name" => "pod-gone"}})
    end
  end
end
