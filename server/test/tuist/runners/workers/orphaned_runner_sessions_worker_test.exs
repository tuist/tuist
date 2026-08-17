defmodule Tuist.Runners.Workers.OrphanedRunnerSessionsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.IngestRepo
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Billing
  alias Tuist.Runners.Job
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Workers.OrphanedRunnerSessionsWorker

  setup :verify_on_exit!

  setup do
    stub(FunWithFlags, :enabled?, fn :runner_pod_reconciliation_paused -> false end)
    :ok
  end

  @selector "tuist.dev/runner=true"

  defp pod(name), do: %{"metadata" => %{"name" => name}}

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

  defp reload(session), do: Repo.reload!(session)

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

  describe "guards" do
    # Guard 1. A failed read is indistinguishable from every Pod having
    # vanished, and acting on it would close the whole fleet's sessions.
    test "does nothing when the cluster read fails" do
      account = account_fixture()
      session = session_fixture(account, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:error, :timeout} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).ended_at == nil
    end

    # Guard 2. Zero Pods returned while sessions are open means a bad
    # selector, wrong namespace, or an empty cache — not an empty fleet.
    test "does nothing when the read returns no pods at all" do
      account = account_fixture()
      session = session_fixture(account, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, []} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).ended_at == nil
    end

    # Guard 3. A session is written before its Pod is labelled and the
    # read is eventually consistent, so a young session is legitimately
    # absent. Rejecting the mock also asserts a quiet fleet costs no
    # apiserver call.
    test "ignores sessions inside the grace window, without reading the cluster" do
      account = account_fixture()
      session = session_fixture(account, "pod-young", age_seconds: 30)

      reject(&K8sClient.list_pods/2)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).ended_at == nil
    end

    test "ignores sessions that are already closed" do
      account = account_fixture()
      closed_at = DateTime.add(DateTime.utc_now(), -600, :second)

      session = session_fixture(account, "pod-closed", ended_at: closed_at)

      reject(&K8sClient.list_pods/2)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert DateTime.compare(reload(session).ended_at, closed_at) == :eq
    end

    test "leaves a session alone while its Pod is present" do
      account = account_fixture()
      session = session_fixture(account, "pod-alive")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-alive")]} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).ended_at == nil
    end
  end

  describe "closing orphans" do
    test "closes a session whose Pod is absent from a complete read" do
      account = account_fixture()
      session = session_fixture(account, "pod-gone", age_seconds: 1800)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).ended_at
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

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})

      expected = DateTime.add(started_at, Billing.max_session_lifetime_seconds(), :second)
      assert reload(session).ended_at |> DateTime.diff(expected, :second) |> abs() <= 5
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

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
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

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})

      assert_received {:recovery, %{count: 1}, %{kind: "orphaned_runner_session"}}
    end
  end

  describe "resolving the real end time" do
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

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert DateTime.compare(reload(session).ended_at, completed_at) == :eq
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

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert DateTime.compare(reload(session).ended_at, executed_job_completion) == :eq
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

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert DateTime.compare(reload(session).ended_at, completed_at) == :eq
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

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})

      expected = DateTime.add(started_at, Billing.max_session_lifetime_seconds(), :second)
      assert reload(session).ended_at |> DateTime.diff(expected, :second) |> abs() <= 5
    end

    test "a ClickHouse failure degrades the batch to the clamp instead of blocking the close" do
      # The capacity fix must not wait on the billing refinement.
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -5 * 24 * 3600, :second)

      session =
        session_fixture(account, "pod-ch-down", age_seconds: 5 * 24 * 3600)

      stub(Jobs, :terminal_completions, fn _ids -> raise "clickhouse unavailable" end)
      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})

      expected = DateTime.add(started_at, Billing.max_session_lifetime_seconds(), :second)
      assert reload(session).ended_at |> DateTime.diff(expected, :second) |> abs() <= 5
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

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
    end
  end

  describe "kill switch" do
    test "does nothing while paused" do
      account = account_fixture()
      session = session_fixture(account, "pod-gone", age_seconds: 3600)

      stub(FunWithFlags, :enabled?, fn :runner_pod_reconciliation_paused -> true end)
      reject(&K8sClient.list_pods/2)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).ended_at == nil
    end
  end
end
