defmodule Tuist.Runners.Workers.PodReconciliationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.IngestRepo
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Billing
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Job
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Workers.PodReconciliationWorker

  setup :verify_on_exit!

  setup do
    stub(FunWithFlags, :enabled?, fn :runner_pod_reconciliation_paused -> false end)
    stub(Jobs, :record_queued, fn _workflow_job_id -> :ok end)
    :ok
  end

  @resources %{platform: :linux, vcpus: 1, memory_gb: 1}
  @selector "tuist.dev/runner=true"

  defp pod(name), do: %{"metadata" => %{"name" => name}}

  defp claim_fixture(account, workflow_job_id, pod_name, opts \\ []) do
    {:ok, _} = Claims.attempt(workflow_job_id, account.id, "fleet-a", pod_name, @resources)

    age = Keyword.get(opts, :age_seconds, 3600)

    updates = [claimed_at: DateTime.add(DateTime.utc_now(), -age, :second)]

    updates =
      case Keyword.get(opts, :missing_for_seconds) do
        nil -> updates
        s -> Keyword.put(updates, :pod_missing_since, DateTime.add(DateTime.utc_now(), -s, :second))
      end

    Repo.update_all(from(c in Claim, where: c.workflow_job_id == ^workflow_job_id), set: updates)
  end

  defp claim(workflow_job_id), do: Repo.get(Claim, workflow_job_id)

  defp session_fixture(account, pod_name, opts \\ []) do
    now = DateTime.utc_now()
    age = Keyword.get(opts, :age_seconds, 3600)

    session =
      Repo.insert!(%RunnerSession{
        account_id: account.id,
        workflow_job_id: Keyword.get_lazy(opts, :workflow_job_id, fn -> System.unique_integer([:positive]) end),
        executed_workflow_job_id: Keyword.get(opts, :executed_workflow_job_id),
        fleet_name: Keyword.get(opts, :fleet_name, "fleet-a"),
        pod_name: pod_name,
        runner_name: "",
        started_at: DateTime.add(now, -age, :second),
        ended_at: Keyword.get(opts, :ended_at),
        inserted_at: DateTime.truncate(now, :second),
        updated_at: DateTime.truncate(now, :second)
      })

    session
  end

  defp reload_session(session), do: Repo.reload!(session)

  defp completed_job_fixture(account, workflow_job_id, completed_at) do
    {1, _} =
      IngestRepo.insert_all(Job, [
        %{
          workflow_job_id: workflow_job_id,
          account_id: account.id,
          fleet_name: "fleet-a",
          platform: "macos",
          vcpus: 6,
          memory_gb: 14,
          repository: "acme/cli",
          workflow_run_id: workflow_job_id * 10,
          run_attempt: 1,
          workflow_name: "CI",
          job_name: "build",
          head_branch: "main",
          head_sha: "deadbeef",
          status: "completed",
          conclusion: "success",
          enqueued_at: completed_at,
          claimed_at: completed_at,
          started_at: completed_at,
          completed_at: completed_at,
          pod_name: "",
          runner_name: "",
          requested_dispatch_label: "",
          updated_at: completed_at
        }
      ])

    :ok
  end

  describe "claim arm: guards" do
    # Guard 1. A failed read is indistinguishable from every Pod having
    # vanished. Acting on it would free the whole fleet's capacity.
    test "does nothing when the cluster read fails" do
      account = account_fixture()
      claim_fixture(account, 9001, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:error, :timeout} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert claim(9001).pod_missing_since == nil
    end

    # Guard 2. Zero Pods returned while claims exist means a bad
    # selector, wrong namespace, or an empty cache — not an empty fleet.
    test "does nothing when the read returns no pods at all" do
      account = account_fixture()
      claim_fixture(account, 9002, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, []} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert claim(9002).pod_missing_since == nil
    end

    # Guard 3. A claim is inserted before its Pod is labelled and the
    # read is eventually consistent, so a young claim is legitimately
    # absent and must never be marked.
    test "ignores claims inside the grace window, without even reading the cluster" do
      account = account_fixture()
      claim_fixture(account, 9003, "pod-young", age_seconds: 30)

      # Nothing is eligible, so the worker must not spend an apiserver
      # call at all. Rejecting the mock asserts both the grace window and
      # that a quiet fleet costs nothing.
      reject(&K8sClient.list_pods/2)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert claim(9003).pod_missing_since == nil
    end

    # Guard 4. One absence only starts the clock. Releasing on a single
    # observation would let any transient read free a live runner.
    test "a first absence marks but does not release" do
      account = account_fixture()
      claim_fixture(account, 9004, "pod-gone")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-other")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})

      assert claim(9004).pod_missing_since
    end

    # Guard 4, the other half. Absence has to be consecutive, so a Pod
    # that reappears resets the clock rather than accumulating toward a
    # release across unrelated blips.
    test "a reappearing pod clears the absence clock" do
      account = account_fixture()
      claim_fixture(account, 9005, "pod-flaky", missing_for_seconds: 240)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-flaky")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})

      assert claim(9005).pod_missing_since == nil
      assert claim(9005)
    end

    # The kill switch has to work without a deploy, so it is checked
    # before anything else the worker does.
    test "does nothing at all while paused" do
      account = account_fixture()
      claim_fixture(account, 9006, "pod-gone", missing_for_seconds: 600)

      stub(FunWithFlags, :enabled?, fn :runner_pod_reconciliation_paused -> true end)
      reject(&K8sClient.list_pods/2)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert claim(9006)
    end
  end

  describe "claim arm: release" do
    # The behaviour the whole worker exists for: capacity held by a Pod
    # that no longer exists, invisible to every store-keyed sweep.
    test "releases a claim whose pod has been absent past the confirmation window" do
      account = account_fixture()
      claim_fixture(account, 9101, "pod-dead", missing_for_seconds: 600)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert claim(9101) == nil
    end

    test "leaves a claim whose pod is present" do
      account = account_fixture()
      claim_fixture(account, 9102, "pod-live", missing_for_seconds: 600)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert claim(9102)
      assert claim(9102).pod_missing_since == nil
    end

    # Absence recorded, but not for long enough yet.
    test "leaves a claim still inside the confirmation window" do
      account = account_fixture()
      claim_fixture(account, 9103, "pod-gone", missing_for_seconds: 60)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert claim(9103)
    end

    # CH before PG. A Pod can vanish while ClickHouse still reads
    # `claimed`, and deleting the claim first would free the slot while
    # stranding the workflow_job for good, since `pick_queued` only
    # selects `queued` and no claim would remain to recover from.
    test "writes the queued state to ClickHouse before dropping the claim" do
      account = account_fixture()
      claim_fixture(account, 9301, "pod-dead", missing_for_seconds: 600)

      test_pid = self()

      expect(Jobs, :record_queued, fn 9301 ->
        send(test_pid, {:recorded_queued, 9301})
        :ok
      end)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})

      assert_received {:recorded_queued, 9301}
      assert claim(9301) == nil
    end

    # If ClickHouse is unavailable we must keep the claim, so the pair is
    # retried intact rather than half-applied.
    test "keeps the claim when the ClickHouse write fails" do
      account = account_fixture()
      claim_fixture(account, 9302, "pod-dead", missing_for_seconds: 600)

      expect(Jobs, :record_queued, fn 9302 -> raise "clickhouse down" end)
      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert claim(9302)
    end

    # Guard 5. A wrong-but-plausible read that survives every other
    # check still cannot free everything at once.
    test "caps releases per tick and leaves the remainder for the next one" do
      account = account_fixture()

      for i <- 1..30 do
        claim_fixture(account, 9200 + i, "pod-dead-#{i}", missing_for_seconds: 600)
      end

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})

      remaining = Repo.aggregate(from(c in Claim, where: c.account_id == ^account.id), :count)
      assert remaining == 5
    end
  end

  describe "session arm: guards" do
    # Guard 1. A failed read is indistinguishable from every Pod having
    # vanished, and acting on it would close the whole fleet's sessions.
    test "does nothing when the cluster read fails" do
      account = account_fixture()
      session = session_fixture(account, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:error, :timeout} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert reload_session(session).ended_at == nil
    end

    # Guard 2. Zero Pods returned while sessions are open means a bad
    # selector, wrong namespace, or an empty cache — not an empty fleet.
    test "does nothing when the read returns no pods at all" do
      account = account_fixture()
      session = session_fixture(account, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, []} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert reload_session(session).ended_at == nil
    end

    # Guard 3. A session is written before its Pod is labelled and the
    # read is eventually consistent, so a young session is legitimately
    # absent. Rejecting the mock also asserts a quiet fleet costs no
    # apiserver call.
    test "ignores sessions inside the grace window, without reading the cluster" do
      account = account_fixture()
      session = session_fixture(account, "pod-young", age_seconds: 30)

      reject(&K8sClient.list_pods/2)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert reload_session(session).ended_at == nil
    end

    test "ignores sessions that are already closed" do
      account = account_fixture()
      closed_at = DateTime.add(DateTime.utc_now(), -600, :second)

      session = session_fixture(account, "pod-closed", ended_at: closed_at)

      reject(&K8sClient.list_pods/2)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert DateTime.compare(reload_session(session).ended_at, closed_at) == :eq
    end

    test "leaves a session alone while its Pod is present" do
      account = account_fixture()
      session = session_fixture(account, "pod-alive")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-alive")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert reload_session(session).ended_at == nil
    end
  end

  describe "session arm: closing orphans" do
    test "closes a session whose Pod is absent from a complete read" do
      account = account_fixture()
      session = session_fixture(account, "pod-gone", age_seconds: 1800)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert reload_session(session).ended_at
    end

    test "drains a long-standing backlog at the billing clamp, not at now" do
      # The rows production accumulated started days ago and were already
      # being charged against `started_at + 6h`. Closing them there keeps
      # the drain billing-neutral.
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -5 * 24 * 3600, :second)

      session =
        session_fixture(account, "pod-ancient", age_seconds: 5 * 24 * 3600)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})

      expected = DateTime.add(started_at, Billing.max_session_lifetime_seconds(), :second)
      assert reload_session(session).ended_at |> DateTime.diff(expected, :second) |> abs() <= 5
    end

    test "a closed orphan stops counting as occupied capacity" do
      # The failure that started this: seventeen phantom sessions on a
      # nine-mini fleet read to the allocator as a saturated fleet.
      account = account_fixture()
      fleet = "fleet-phantom"

      session_fixture(account, "pod-phantom",
        fleet_name: fleet,
        age_seconds: 1800
      )

      assert RunnerSessions.occupied_counts_per_fleet()[fleet] == 1

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert Map.get(RunnerSessions.occupied_counts_per_fleet(), fleet, 0) == 0
    end

    test "emits recovery telemetry for the closed sessions" do
      account = account_fixture()
      session_fixture(account, "pod-gone", age_seconds: 3600)

      handler_id = "orphaned-runner-sessions-test-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:tuist, :runners, :recovery],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:recovery, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})

      assert_received {:recovery, %{count: 1}, %{kind: "orphaned_runner_session"}}
    end
  end

  describe "session arm: resolving the real end time" do
    test "closes at the job's completion rather than the clamp" do
      # This is what keeps the backlog drain from being a no-op on
      # billing: 90 seconds of real work bills as 90 seconds, not as the
      # six-hour bound the open row was already charged against.
      account = account_fixture()
      now = DateTime.utc_now()
      started_at = DateTime.add(now, -5 * 24 * 3600, :second)
      completed_at = DateTime.add(started_at, 90, :second)

      session =
        session_fixture(account, "pod-completed",
          workflow_job_id: 79_001,
          age_seconds: 5 * 24 * 3600
        )

      completed_job_fixture(account, 79_001, completed_at)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert DateTime.compare(reload_session(session).ended_at, completed_at) == :eq
    end

    test "prefers the job GitHub proved ran over the job the claim was minted for" do
      # A runner handed a sibling's job: the executed job's completion is
      # what released the Pod, so it dates the session's end.
      account = account_fixture()
      now = DateTime.utc_now()
      started_at = DateTime.add(now, -3600, :second)
      claimed_job_completion = DateTime.add(started_at, 60, :second)
      executed_job_completion = DateTime.add(started_at, 600, :second)

      session =
        session_fixture(account, "pod-sibling",
          workflow_job_id: 79_002,
          executed_workflow_job_id: 79_003,
          age_seconds: 3600
        )

      completed_job_fixture(account, 79_002, claimed_job_completion)
      completed_job_fixture(account, 79_003, executed_job_completion)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert DateTime.compare(reload_session(session).ended_at, executed_job_completion) == :eq
    end

    test "falls back to the claim-time job when GitHub never proved an execution" do
      account = account_fixture()
      now = DateTime.utc_now()
      started_at = DateTime.add(now, -3600, :second)
      completed_at = DateTime.add(started_at, 300, :second)

      session =
        session_fixture(account, "pod-unproven",
          workflow_job_id: 79_004,
          age_seconds: 3600
        )

      completed_job_fixture(account, 79_004, completed_at)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert DateTime.compare(reload_session(session).ended_at, completed_at) == :eq
    end

    test "falls back to the clamp for a job that never reached a terminal state" do
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -5 * 24 * 3600, :second)

      session =
        session_fixture(account, "pod-never-terminal",
          workflow_job_id: 79_005,
          age_seconds: 5 * 24 * 3600
        )

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})

      expected = DateTime.add(started_at, Billing.max_session_lifetime_seconds(), :second)
      assert reload_session(session).ended_at |> DateTime.diff(expected, :second) |> abs() <= 5
    end

    test "a ClickHouse failure degrades the batch to the clamp instead of blocking the close" do
      # The capacity fix must not wait on the billing refinement.
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -5 * 24 * 3600, :second)

      session =
        session_fixture(account, "pod-ch-down", age_seconds: 5 * 24 * 3600)

      stub(Jobs, :terminal_completions, fn _ids -> raise "clickhouse unavailable" end)
      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})

      expected = DateTime.add(started_at, Billing.max_session_lifetime_seconds(), :second)
      assert reload_session(session).ended_at |> DateTime.diff(expected, :second) |> abs() <= 5
    end

    test "resolves the whole batch with a single ClickHouse query" do
      account = account_fixture()

      for i <- 1..3 do
        session_fixture(account, "pod-batch-#{i}", workflow_job_id: 79_100 + i, age_seconds: 3600)
      end

      expect(Jobs, :terminal_completions, 1, fn ids ->
        assert length(ids) == 3
        %{}
      end)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
    end
  end

  describe "session arm: kill switch" do
    test "does nothing while paused" do
      account = account_fixture()
      session = session_fixture(account, "pod-gone", age_seconds: 3600)

      stub(FunWithFlags, :enabled?, fn :runner_pod_reconciliation_paused -> true end)
      reject(&K8sClient.list_pods/2)

      assert :ok = PodReconciliationWorker.perform(%Oban.Job{})
      assert reload_session(session).ended_at == nil
    end
  end
end
