defmodule Tuist.Runners.Workers.OrphanedRunnerSessionsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Billing
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
        workflow_job_id: System.unique_integer([:positive]),
        fleet_name: Keyword.get(opts, :fleet_name, "fleet-a"),
        pod_name: pod_name,
        runner_name: "",
        started_at: DateTime.add(now, -age, :second),
        ended_at: Keyword.get(opts, :ended_at),
        inserted_at: DateTime.truncate(now, :second),
        updated_at: DateTime.truncate(now, :second)
      })

    case Keyword.get(opts, :missing_for_seconds) do
      nil -> session
      s -> tap(session, &RunnerSessions.mark_pods_missing([&1.id], DateTime.add(now, -s, :second)))
    end
  end

  defp reload(session), do: Repo.reload!(session)

  describe "guards" do
    # Guard 1. A failed read is indistinguishable from every Pod having
    # vanished, and acting on it would close the whole fleet's sessions.
    test "does nothing when the cluster read fails" do
      account = account_fixture()
      session = session_fixture(account, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:error, :timeout} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).pod_missing_since == nil
    end

    # Guard 2. Zero Pods returned while sessions are open means a bad
    # selector, wrong namespace, or an empty cache — not an empty fleet.
    test "does nothing when the read returns no pods at all" do
      account = account_fixture()
      session = session_fixture(account, "pod-1")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, []} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).pod_missing_since == nil
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
      assert reload(session).pod_missing_since == nil
    end

    test "ignores sessions that are already closed" do
      account = account_fixture()

      session =
        session_fixture(account, "pod-closed", ended_at: DateTime.add(DateTime.utc_now(), -600, :second))

      reject(&K8sClient.list_pods/2)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).pod_missing_since == nil
    end

    # Guard 4. One absence only starts the clock.
    test "a first absence marks but does not close" do
      account = account_fixture()
      session = session_fixture(account, "pod-gone")

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-other")]} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})

      reloaded = reload(session)
      assert reloaded.pod_missing_since
      assert reloaded.ended_at == nil
    end

    test "a Pod that reappears resets the clock" do
      account = account_fixture()
      session = session_fixture(account, "pod-flapping", missing_for_seconds: 400)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-flapping")]} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})

      reloaded = reload(session)
      assert reloaded.pod_missing_since == nil
      assert reloaded.ended_at == nil
    end
  end

  describe "closing confirmed orphans" do
    test "closes a session whose Pod has been absent past the confirm window" do
      account = account_fixture()
      session = session_fixture(account, "pod-gone", age_seconds: 1800, missing_for_seconds: 400)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).ended_at
    end

    test "leaves a session whose Pod is still absent but not yet confirmed" do
      account = account_fixture()
      session = session_fixture(account, "pod-gone", missing_for_seconds: 60)

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).ended_at == nil
    end

    test "drains a long-standing backlog at the billing clamp, not at now" do
      # The rows production accumulated started days ago and were already
      # being charged against `started_at + 6h`. Closing them there keeps
      # the drain billing-neutral.
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -5 * 24 * 3600, :second)

      session =
        session_fixture(account, "pod-ancient",
          age_seconds: 5 * 24 * 3600,
          missing_for_seconds: 400
        )

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
        age_seconds: 1800,
        missing_for_seconds: 400
      )

      assert RunnerSessions.occupied_counts_per_fleet()[fleet] == 1

      expect(K8sClient, :list_pods, fn _ns, @selector -> {:ok, [pod("pod-live")]} end)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert Map.get(RunnerSessions.occupied_counts_per_fleet(), fleet, 0) == 0
    end

    test "emits recovery telemetry for the closed sessions" do
      account = account_fixture()
      session_fixture(account, "pod-gone", missing_for_seconds: 400)

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

  describe "kill switch" do
    test "does nothing while paused" do
      account = account_fixture()
      session = session_fixture(account, "pod-gone", missing_for_seconds: 400)

      stub(FunWithFlags, :enabled?, fn :runner_pod_reconciliation_paused -> true end)
      reject(&K8sClient.list_pods/2)

      assert :ok = OrphanedRunnerSessionsWorker.perform(%Oban.Job{})
      assert reload(session).ended_at == nil
    end
  end
end
