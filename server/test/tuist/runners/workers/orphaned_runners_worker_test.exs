defmodule Tuist.Runners.Workers.OrphanedRunnersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Telemetry
  alias Tuist.Runners.Workers.OrphanedRunnersWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  setup :verify_on_exit!

  setup do
    stub(K8sClient, :list_pods, fn _namespace, _selector -> {:ok, pod_items(["pod-1"])} end)

    stub(GitHubClient, :workflow_run_status, fn _installation, _repository, _run_id ->
      {:ok, %{status: "in_progress", conclusion: nil}}
    end)

    :ok
  end

  defp candidate(opts) do
    %{
      workflow_job_id: Keyword.get(opts, :workflow_job_id, 76_348_428_905),
      account_id: Keyword.get(opts, :account_id, 3),
      repository: Keyword.get(opts, :repository, "tuist/tuist"),
      workflow_run_id: Keyword.get(opts, :workflow_run_id, 32_985_506_614),
      claimed_at: Keyword.get(opts, :claimed_at, ~U[2026-05-16 21:14:06.616167Z]),
      started_at: Keyword.get(opts, :started_at, ~U[2026-05-16 21:14:07.711527Z]),
      pod_name: Keyword.get(opts, :pod_name, "pod-1"),
      fleet_name: Keyword.get(opts, :fleet_name, "tuist-tuist-runner-pool-macos-26-6")
    }
  end

  defp pod_items(names), do: Enum.map(names, &%{"metadata" => %{"name" => &1}})

  defp account_fixture do
    TuistTestSupport.Fixtures.AccountsFixtures.organization_fixture(name: "tuist-#{System.unique_integer([:positive])}").account
  end

  describe "perform/1" do
    test "completes instead of re-queueing when the parent workflow run is already completed" do
      # A run that ends in `startup_failure` leaves its remaining jobs
      # `queued` on GitHub permanently: the run is terminal, so no runner
      # is ever assigned, yet the per-job endpoint keeps answering
      # `queued`. Re-queueing on that answer alone returns the job to the
      # head of the fleet queue (dispatch orders by oldest `enqueued_at`),
      # where the next Pod claims it, strands, and is recovered again.
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :list_orphaned_running, fn _threshold -> [orphan] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      expect(GitHubClient, :workflow_run_status, fn _installation, "tuist/tuist", run_id ->
        assert run_id == orphan.workflow_run_id
        {:ok, %{status: "completed", conclusion: "startup_failure"}}
      end)

      reject(&Claims.release/2)

      expect(Claims, :complete, fn wfid ->
        assert wfid == orphan.workflow_job_id
        :ok
      end)

      expect(Jobs, :complete, fn wfid, conclusion ->
        assert wfid == orphan.workflow_job_id
        assert conclusion == "startup_failure"
        {:ok, %{}}
      end)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "still re-queues when the parent workflow run is not terminal" do
      # The run is live, so `queued` means the runner never came up and
      # the job is genuinely re-dispatchable.
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :list_orphaned_running, fn _threshold -> [orphan] end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      expect(GitHubClient, :workflow_run_status, fn _i, _r, _run_id ->
        {:ok, %{status: "in_progress", conclusion: nil}}
      end)

      reject(&Jobs.complete/2)

      expect(Claims, :release, fn wfid, handle ->
        assert wfid == orphan.workflow_job_id
        assert handle == orphan.claimed_at
        :ok
      end)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

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

      reject(&Claims.release/2)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "recovers an aged row whose Pod is gone even when its claim records a sibling execution" do
      # Age decides candidacy, absence decides evidence, and the two must
      # stay separate. A row that crosses the floor before the first
      # successful cluster read (a paused worker, an Oban backlog, a run
      # of failed reads) would otherwise be filed under `:aged_out` for
      # the rest of its life and never regain the absence that settles the
      # busy guard, leaving it stranded until `PodReconciliationWorker`.
      account = account_fixture()
      orphan = candidate(account_id: account.id, pod_name: "pod-gone")

      expect(Jobs, :list_orphaned_running, fn _threshold -> [orphan] end)
      expect(Jobs, :list_running_since, fn _threshold -> [] end)

      expect(K8sClient, :list_pods, fn _namespace, _selector ->
        {:ok, pod_items(["pod-alive"])}
      end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _installation, _repository, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      stub(Claims, :executing?, fn _wfid -> true end)

      expect(Claims, :release, fn wfid, handle ->
        assert wfid == orphan.workflow_job_id
        assert handle == orphan.claimed_at
        :ok
      end)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "leaves an aged row alone when its claim records a sibling execution" do
      # Without evidence the Pod is gone, a claim recording an execution is
      # a runner that is genuinely busy on some job. Age alone must not
      # release it: the executor's `completed` webhook would then find
      # nothing to free and the account would under-count a live runner.
      account = account_fixture()
      orphan = candidate(account_id: account.id)

      expect(Jobs, :list_orphaned_running, fn _threshold -> [orphan] end)
      expect(Jobs, :list_running_since, fn _threshold -> [] end)

      # The Pod is still in the cluster, so there is no absence to settle
      # the guard with: age alone is all this row has.
      expect(K8sClient, :list_pods, fn _namespace, _selector ->
        {:ok, pod_items([orphan.pod_name])}
      end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _installation, _repository, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      stub(Claims, :executing?, fn _wfid -> true end)

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

  describe "perform/1 with a Pod that is gone" do
    test "recovers a row too young for the staleness floor once its Pod is gone" do
      # The age gate is a stand-in for evidence: the sweep cannot tell a
      # healthy in-flight build from an orphan without asking GitHub, so
      # it waits 5 minutes before asking. A Pod that is no longer in the
      # cluster is that evidence, so the wait buys nothing — and the
      # push signal that carries it (`pods/stopped`) is best-effort.
      account = account_fixture()
      orphan = candidate(account_id: account.id, pod_name: "pod-gone")

      expect(Jobs, :list_orphaned_running, fn _threshold -> [] end)
      expect(Jobs, :list_running_since, fn _threshold -> [orphan] end)

      expect(K8sClient, :list_pods, fn _namespace, "tuist.dev/runner=true" ->
        {:ok, pod_items(["pod-alive"])}
      end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _installation, _repository, wfid ->
        assert wfid == orphan.workflow_job_id
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      expect(Claims, :release, fn _wfid, _handle -> :ok end)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "recovers a row whose Pod is gone even when its claim recorded a sibling execution" do
      # The busy guard in the queued branch exists because a Pod handed a
      # sibling's job is still working, so releasing on the claimed job's
      # GitHub status alone would delete a live runner's reservation
      # mid-job. A Pod that is gone is not working. Leaving the guard in
      # force here sends exactly the population this arm targets (GitHub
      # binds by label set, so executing a sibling's job is the common
      # shape) back to `PodReconciliationWorker`'s 10-minute grace plus
      # 5-minute confirmation.
      account = account_fixture()
      orphan = candidate(account_id: account.id, pod_name: "pod-gone")

      expect(Jobs, :list_orphaned_running, fn _threshold -> [] end)
      expect(Jobs, :list_running_since, fn _threshold -> [orphan] end)

      expect(K8sClient, :list_pods, fn _namespace, _selector ->
        {:ok, pod_items(["pod-alive"])}
      end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _installation, _repository, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      # The claim survives with `executed_workflow_job_id` set: the Pod
      # died mid-sibling, so no `completed` webhook ever released it.
      stub(Claims, :executing?, fn _wfid -> true end)

      expect(Claims, :release, fn wfid, handle ->
        assert wfid == orphan.workflow_job_id
        assert handle == orphan.claimed_at
        :ok
      end)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "leaves a young row alone while its Pod is still in the cluster" do
      # A Pod that is present is either booting or executing; the age
      # gate owns that case and only GitHub can settle it.
      orphan = candidate(pod_name: "pod-alive")

      expect(Jobs, :list_orphaned_running, fn _threshold -> [] end)
      expect(Jobs, :list_running_since, fn _threshold -> [orphan] end)

      expect(K8sClient, :list_pods, fn _namespace, _selector ->
        {:ok, pod_items(["pod-alive", "pod-other"])}
      end)

      reject(&GitHubClient.get_workflow_job/3)
      reject(&Claims.release/2)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "widens nothing when the cluster read fails" do
      # A partial read is indistinguishable from mass absence, and
      # acting on it would recover live runners' rows in bulk.
      orphan = candidate(pod_name: "pod-gone")

      expect(Jobs, :list_orphaned_running, fn _threshold -> [] end)
      expect(Jobs, :list_running_since, fn _threshold -> [orphan] end)
      expect(K8sClient, :list_pods, fn _namespace, _selector -> {:error, :timeout} end)

      reject(&GitHubClient.get_workflow_job/3)
      reject(&Claims.release/2)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "widens nothing when the cluster read comes back empty" do
      # Rows are open, so the fleet cannot really be empty: a wrong
      # selector or an empty page reads the same as every Pod vanishing.
      orphan = candidate(pod_name: "pod-gone")

      expect(Jobs, :list_orphaned_running, fn _threshold -> [] end)
      expect(Jobs, :list_running_since, fn _threshold -> [orphan] end)
      expect(K8sClient, :list_pods, fn _namespace, _selector -> {:ok, []} end)

      reject(&GitHubClient.get_workflow_job/3)
      reject(&Claims.release/2)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "does not read the cluster when no row is running at all" do
      # Steady state: nothing to ask about, so the arm costs one query
      # and no apiserver traffic.
      expect(Jobs, :list_orphaned_running, fn _threshold -> [] end)
      expect(Jobs, :list_running_since, fn _threshold -> [] end)

      reject(&K8sClient.list_pods/2)

      assert :ok = OrphanedRunnersWorker.perform(%Oban.Job{})
    end

    test "never treats a row without a Pod name as absent" do
      # A `running` row always carries the Pod that minted it, but an
      # empty name would match no Pod and recover unconditionally.
      orphan = candidate(pod_name: "")

      expect(Jobs, :list_orphaned_running, fn _threshold -> [] end)
      expect(Jobs, :list_running_since, fn _threshold -> [orphan] end)

      expect(K8sClient, :list_pods, fn _namespace, _selector ->
        {:ok, pod_items(["pod-alive"])}
      end)

      reject(&GitHubClient.get_workflow_job/3)
      reject(&Claims.release/2)

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

      reject(&Claims.release/2)

      assert :ok =
               OrphanedRunnersWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => orphan.workflow_job_id, "pod_name" => orphan.pod_name}
               })
    end

    test "recovers even when the pod-stopped release left the claim behind" do
      # Targeted mode used to satisfy the busy guard only as a side effect
      # of the controller's report having deleted the claim first. That
      # made a correctness path depend on one release winning a race it is
      # not guaranteed to win. The evidence that settles the guard is the
      # Pod having stopped, which is the caller's whole premise.
      account = account_fixture()
      orphan = candidate(account_id: account.id, pod_name: "pod-stopped")

      expect(Jobs, :get_orphaned_running, fn _wfid -> orphan end)

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _installation, _repository, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      stub(Claims, :executing?, fn _wfid -> true end)

      expect(Claims, :release, fn wfid, handle ->
        assert wfid == orphan.workflow_job_id
        assert handle == orphan.claimed_at
        :ok
      end)

      assert :ok =
               OrphanedRunnersWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => orphan.workflow_job_id, "pod_name" => "pod-stopped"}
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
      reject(&Claims.release/2)

      assert :ok =
               OrphanedRunnersWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => replacement.workflow_job_id, "pod_name" => "pod-that-stopped"}
               })
    end

    test "re-queues the lifecycle row when the pod-stopped report already released the claim" do
      # The real targeted flow: `Claims.release_by_pod_name/1` deleted
      # the claim at pod stop without touching the lifecycle row, so by
      # the time this run cross-checks GitHub there is no claim left for
      # `Claims.release/2` to delete. The row must still move back to
      # `queued` — dispatch reads it, and GitHub never re-announces a job
      # it still considers queued — so the worker finishes the release
      # by handle instead of treating the missing claim as "someone
      # else's now".
      account = account_fixture()
      workflow_job_id = 76_348_428_990
      pod_name = "pod-stopped"

      :ok =
        WorkflowJobs.upsert_queued(%{
          workflow_job_id: workflow_job_id,
          account_id: account.id,
          fleet_name: "fleet-targeted",
          repository: "tuist/tuist"
        })

      {:ok, _claim} =
        Claims.attempt(workflow_job_id, account.id, "fleet-targeted", pod_name, %{
          platform: :linux,
          vcpus: 1,
          memory_gb: 1
        })

      :ok = mark_running!(workflow_job_id, "runner-targeted")
      assert [^workflow_job_id] = Claims.release_by_pod_name(pod_name)
      assert Repo.get!(WorkflowJob, workflow_job_id).status == "running"

      expect(Tuist.VCS, :get_github_app_installation_for_account, fn _id ->
        {:ok, %{installation_id: 1, client_url: "https://github.com"}}
      end)

      expect(GitHubClient, :get_workflow_job, fn _i, _r, _wfid ->
        {:ok, %{status: "queued", conclusion: nil, runner_name: nil}}
      end)

      assert :ok =
               OrphanedRunnersWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => workflow_job_id, "pod_name" => pod_name}
               })

      row = Repo.get!(WorkflowJob, workflow_job_id)
      assert row.status == "queued"
      assert row.pod_name == nil
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

  # Production threads the caller's own claim handle into `mark_running/3`;
  # these tests only need "promote the claim that exists", so they read it
  # back. The guard itself is covered in the `mark_running/3` describe.
  defp mark_running!(workflow_job_id, runner_name) do
    claim = Repo.one!(from(c in Tuist.Runners.Claim, where: c.workflow_job_id == ^workflow_job_id))
    Claims.mark_running(workflow_job_id, runner_name, claim.claimed_at)
  end
end
