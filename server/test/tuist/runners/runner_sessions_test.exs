defmodule Tuist.Runners.RunnerSessionsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Billing
  alias Tuist.Runners.Claims
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.RunnerSessions

  defp session_fixture(account, attrs) do
    defaults = %{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "fleet-a",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      started_at: DateTime.utc_now(),
      ended_at: nil,
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    Repo.insert!(struct(RunnerSession, Map.merge(defaults, Map.new(attrs))))
  end

  describe "occupied_counts_per_fleet/0" do
    test "counts the distinct union of claims and open sessions" do
      account = account_fixture()
      fleet = "fleet-occupied"
      pod_name = "pod-claimed-and-open"

      assert {:ok, _claim} =
               Claims.attempt(71_001, account.id, fleet, pod_name, %{
                 platform: :macos,
                 vcpus: 6,
                 memory_gb: 14
               })

      session_fixture(account,
        workflow_job_id: 71_001,
        fleet_name: fleet,
        pod_name: pod_name
      )

      session_fixture(account,
        workflow_job_id: 71_002,
        fleet_name: fleet,
        pod_name: "pod-session-tail"
      )

      assert RunnerSessions.occupied_counts_per_fleet()[fleet] == 2
    end

    test "ignores closed and stale session-only occupancy" do
      account = account_fixture()
      fleet = "fleet-no-longer-occupied"
      now = DateTime.utc_now()

      session_fixture(account,
        fleet_name: fleet,
        pod_name: "pod-closed",
        started_at: DateTime.add(now, -300, :second),
        ended_at: DateTime.add(now, -60, :second)
      )

      session_fixture(account,
        fleet_name: fleet,
        pod_name: "pod-stale-open",
        started_at: DateTime.add(now, -7 * 3600, :second)
      )

      assert Map.get(RunnerSessions.occupied_counts_per_fleet(), fleet, 0) == 0
    end
  end

  describe "p95_concurrent_last_hour/1" do
    test "returns zero for a fleet with no sessions" do
      assert RunnerSessions.p95_concurrent_last_hour("fleet-empty") == 0
    end

    test "keeps a sparse completed session visible without zero-demand buckets" do
      account = account_fixture()
      fleet = "fleet-sparse-history"
      now = DateTime.utc_now()

      session_fixture(account,
        fleet_name: fleet,
        started_at: DateTime.add(now, -40 * 60, :second),
        ended_at: DateTime.add(now, -39 * 60, :second)
      )

      assert RunnerSessions.p95_concurrent_last_hour(fleet) == 1
    end

    test "reports overlapping session capacity" do
      account = account_fixture()
      fleet = "fleet-overlap-history"
      now = DateTime.utc_now()

      for workflow_job_id <- [72_001, 72_002] do
        session_fixture(account,
          workflow_job_id: workflow_job_id,
          fleet_name: fleet,
          started_at: DateTime.add(now, -10 * 60, :second),
          ended_at: DateTime.add(now, -5 * 60, :second)
        )
      end

      assert RunnerSessions.p95_concurrent_last_hour(fleet) == 2
    end

    test "clamps an orphaned open session out of the forecast" do
      account = account_fixture()
      fleet = "fleet-stale-history"

      session_fixture(account,
        fleet_name: fleet,
        started_at: DateTime.add(DateTime.utc_now(), -8 * 3600, :second)
      )

      assert RunnerSessions.p95_concurrent_last_hour(fleet) == 0
    end
  end

  describe "close_by_pod_name/2" do
    test "sets ended_at on the open session matching pod_name" do
      account = account_fixture()
      pod_name = "tuist-macos-runner-aaaa1111"
      started_at = ~U[2026-05-26 12:00:00.000000Z]
      ended_at = ~U[2026-05-26 12:05:00.000000Z]

      session_fixture(account, pod_name: pod_name, started_at: started_at)

      assert {:ok, %RunnerSession{} = updated} = RunnerSessions.close_by_pod_name(pod_name, ended_at)
      assert DateTime.compare(updated.ended_at, ended_at) == :eq
    end

    test "no-ops when no session exists for the pod_name" do
      assert {:ok, :no_open_session} =
               RunnerSessions.close_by_pod_name("ghost-pod", DateTime.utc_now())
    end

    test "under-bill bias: re-emit with a later timestamp keeps the earlier ended_at" do
      account = account_fixture()
      pod_name = "tuist-linux-runner-bbbb2222"
      started_at = ~U[2026-05-26 12:00:00.000000Z]
      first_close = ~U[2026-05-26 12:05:00.000000Z]
      late_redelivery = ~U[2026-05-26 12:10:00.000000Z]

      session_fixture(account, pod_name: pod_name, started_at: started_at)

      {:ok, _} = RunnerSessions.close_by_pod_name(pod_name, first_close)
      {:ok, redelivered} = RunnerSessions.close_by_pod_name(pod_name, late_redelivery)

      # The late re-delivery's timestamp would have extended the
      # billed window if accepted. Under-bill bias keeps the
      # earlier close.
      assert DateTime.compare(redelivered.ended_at, first_close) == :eq
    end

    test "re-emit with an earlier timestamp clamps the ended_at down" do
      account = account_fixture()
      pod_name = "tuist-linux-runner-cccc3333"
      started_at = ~U[2026-05-26 12:00:00.000000Z]
      first_close = ~U[2026-05-26 12:10:00.000000Z]
      earlier_redelivery = ~U[2026-05-26 12:05:00.000000Z]

      session_fixture(account, pod_name: pod_name, started_at: started_at)

      {:ok, _} = RunnerSessions.close_by_pod_name(pod_name, first_close)
      {:ok, redelivered} = RunnerSessions.close_by_pod_name(pod_name, earlier_redelivery)

      # Earlier ended_at always wins — under-bill is the safer
      # direction whichever side of the disagreement we land on.
      assert DateTime.compare(redelivered.ended_at, earlier_redelivery) == :eq
    end

    test "raises on empty pod_name" do
      assert_raise FunctionClauseError, fn ->
        RunnerSessions.close_by_pod_name("", DateTime.utc_now())
      end
    end
  end

  describe "live_pod_names/0" do
    test "returns the pod_names of sessions whose ended_at is nil" do
      account = account_fixture()
      session_fixture(account, pod_name: "pod-open-1", ended_at: nil)
      session_fixture(account, pod_name: "pod-open-2", ended_at: nil)
      session_fixture(account, pod_name: "pod-closed", ended_at: DateTime.utc_now())

      names = RunnerSessions.live_pod_names()

      assert MapSet.member?(names, "pod-open-1")
      assert MapSet.member?(names, "pod-open-2")
      refute MapSet.member?(names, "pod-closed")
    end

    test "deduplicates pod_names across multiple open sessions for the same pod" do
      # Re-claims insert new RunnerSession rows for the same pod_name
      # (see the module doc). The protect-set is a MapSet of names, so
      # the duplicate must collapse cleanly.
      account = account_fixture()
      session_fixture(account, pod_name: "pod-reclaim", ended_at: nil)
      session_fixture(account, pod_name: "pod-reclaim", ended_at: nil)

      assert MapSet.size(RunnerSessions.live_pod_names()) == 1
    end

    test "returns an empty set when no sessions are open" do
      account = account_fixture()
      session_fixture(account, pod_name: "pod-already-closed", ended_at: DateTime.utc_now())

      assert MapSet.equal?(RunnerSessions.live_pod_names(), MapSet.new())
    end
  end

  describe "live_for_pod/1" do
    test "returns the latest open runner session binding for a pod" do
      account = account_fixture()
      pod_name = "pod-live-binding"

      session_fixture(account,
        workflow_job_id: 81_001,
        pod_name: pod_name,
        fleet_name: "fleet-old",
        started_at: ~U[2026-05-26 12:00:00.000000Z]
      )

      session_fixture(account,
        workflow_job_id: 81_002,
        pod_name: pod_name,
        fleet_name: "fleet-new",
        started_at: ~U[2026-05-26 12:05:00.000000Z]
      )

      assert {:ok,
              %{
                workflow_job_id: 81_002,
                account_id: account_id,
                fleet_name: "fleet-new",
                pod_name: ^pod_name
              }} = RunnerSessions.live_for_pod(pod_name)

      assert account_id == account.id
    end

    test "ignores closed runner sessions" do
      account = account_fixture()
      session_fixture(account, pod_name: "pod-closed-binding", ended_at: DateTime.utc_now())

      assert RunnerSessions.live_for_pod("pod-closed-binding") == :error
    end
  end

  describe "live_for_workflow_job/2" do
    test "returns the latest open runner session binding for a workflow job and account" do
      account = account_fixture()

      session_fixture(account,
        workflow_job_id: 82_001,
        pod_name: "pod-job-old",
        fleet_name: "fleet-old",
        started_at: ~U[2026-05-26 12:00:00.000000Z]
      )

      session_fixture(account,
        workflow_job_id: 82_001,
        pod_name: "pod-job-new",
        fleet_name: "fleet-new",
        started_at: ~U[2026-05-26 12:05:00.000000Z]
      )

      assert {:ok,
              %{
                workflow_job_id: 82_001,
                account_id: account_id,
                fleet_name: "fleet-new",
                pod_name: "pod-job-new"
              }} = RunnerSessions.live_for_workflow_job(82_001, account.id)

      assert account_id == account.id
    end

    test "does not cross account boundaries" do
      account = account_fixture()
      other_account = account_fixture()
      session_fixture(account, workflow_job_id: 82_002, pod_name: "pod-owner")

      assert RunnerSessions.live_for_workflow_job(82_002, other_account.id) == :error
    end
  end

  describe "executed_job_for_pod/1" do
    test "resolves the pod to the job GitHub proved it is running" do
      account = account_fixture()
      session_fixture(account, pod_name: "pod-1", runner_name: "runner-1", workflow_job_id: 9001)
      assert :matched = RunnerSessions.record_execution("runner-1", 9001, account.id)

      assert {:ok, %{workflow_job_id: 9001, account_id: account_id}} =
               RunnerSessions.executed_job_for_pod("pod-1")

      assert account_id == account.id
    end

    test "resolves to the executed job, not the claimed one" do
      account = account_fixture()
      session_fixture(account, pod_name: "pod-2", runner_name: "runner-2", workflow_job_id: 9002)
      assert :mismatch = RunnerSessions.record_execution("runner-2", 9099, account.id)

      assert {:ok, %{workflow_job_id: 9099}} = RunnerSessions.executed_job_for_pod("pod-2")
    end

    test "returns :error until execution is proven (never guesses the claimed job)" do
      account = account_fixture()
      session_fixture(account, pod_name: "pod-3", runner_name: "runner-3", workflow_job_id: 9003)

      assert RunnerSessions.executed_job_for_pod("pod-3") == :error
    end

    test "returns :error for a pod with no session" do
      assert RunnerSessions.executed_job_for_pod("ghost-pod") == :error
    end

    test "returns :error once the session is closed" do
      account = account_fixture()
      session_fixture(account, pod_name: "pod-4", runner_name: "runner-4", workflow_job_id: 9004)
      assert :matched = RunnerSessions.record_execution("runner-4", 9004, account.id)
      {:ok, _} = RunnerSessions.close_by_pod_name("pod-4", DateTime.utc_now())

      assert RunnerSessions.executed_job_for_pod("pod-4") == :error
    end
  end

  describe "record_execution/2" do
    test "binds the executed job on the open session and reports :matched" do
      account = account_fixture()
      session = session_fixture(account, runner_name: "runner-a", workflow_job_id: 8001)

      assert :matched = RunnerSessions.record_execution("runner-a", 8001, account.id)

      assert Repo.get!(RunnerSession, session.id).executed_workflow_job_id == 8001
    end

    test "reports :mismatch and binds the real job GitHub ran" do
      account = account_fixture()
      session = session_fixture(account, runner_name: "runner-b", workflow_job_id: 8002)

      assert :mismatch = RunnerSessions.record_execution("runner-b", 8099, account.id)

      assert Repo.get!(RunnerSession, session.id).executed_workflow_job_id == 8099
    end

    test "prefers the open session over a closed one for the same runner_name" do
      account = account_fixture()
      # A closed prior session and a fresh open one can share a runner_name
      # in theory; the open row is the one currently executing.
      session_fixture(account, runner_name: "runner-c", workflow_job_id: 8003, ended_at: DateTime.utc_now())
      open = session_fixture(account, runner_name: "runner-c", workflow_job_id: 8004, ended_at: nil)

      assert :matched = RunnerSessions.record_execution("runner-c", 8004, account.id)
      assert Repo.get!(RunnerSession, open.id).executed_workflow_job_id == 8004
    end

    test "falls back to the durable closed session when the pod is already gone" do
      account = account_fixture()
      closed = session_fixture(account, runner_name: "runner-d", workflow_job_id: 8005, ended_at: DateTime.utc_now())

      # `completed` backstop after a fast job's pod terminated.
      assert :matched = RunnerSessions.record_execution("runner-d", 8005, account.id)
      assert Repo.get!(RunnerSession, closed.id).executed_workflow_job_id == 8005
    end

    test "reports :unknown_runner when no session carries the runner_name" do
      account = account_fixture()
      assert :unknown_runner = RunnerSessions.record_execution("ghost", 8100, account.id)
    end

    test "is a no-op for an empty runner_name" do
      account = account_fixture()
      assert :unknown_runner = RunnerSessions.record_execution("", 8101, account.id)
    end
  end

  describe "clamped_open_session_counts_per_fleet/0" do
    test "counts only open sessions past the six-hour bound" do
      account = account_fixture()
      fleet = "fleet-clamped"
      now = DateTime.utc_now()

      session_fixture(account,
        fleet_name: fleet,
        pod_name: "pod-leaked",
        started_at: DateTime.add(now, -7 * 3600, :second)
      )

      session_fixture(account,
        fleet_name: fleet,
        pod_name: "pod-young-open",
        started_at: DateTime.add(now, -600, :second)
      )

      session_fixture(account,
        fleet_name: fleet,
        pod_name: "pod-old-but-closed",
        started_at: DateTime.add(now, -8 * 3600, :second),
        ended_at: DateTime.add(now, -7 * 3600, :second)
      )

      assert RunnerSessions.clamped_open_session_counts_per_fleet()[fleet] == 1
    end

    test "omits fleets with nothing past the bound" do
      account = account_fixture()
      fleet = "fleet-healthy"

      session_fixture(account, fleet_name: fleet, started_at: DateTime.utc_now())

      refute Map.has_key?(RunnerSessions.clamped_open_session_counts_per_fleet(), fleet)
    end
  end

  describe "pod reconciliation" do
    test "list_open_for_pod_reconciliation/1 excludes closed and young sessions" do
      account = account_fixture()
      now = DateTime.utc_now()
      threshold = DateTime.add(now, -900, :second)

      old_open =
        session_fixture(account,
          pod_name: "pod-old-open",
          started_at: DateTime.add(now, -3600, :second)
        )

      session_fixture(account,
        pod_name: "pod-just-started",
        started_at: DateTime.add(now, -30, :second)
      )

      session_fixture(account,
        pod_name: "pod-already-closed",
        started_at: DateTime.add(now, -3600, :second),
        ended_at: DateTime.add(now, -1800, :second)
      )

      assert [%{id: id, pod_name: "pod-old-open"}] =
               RunnerSessions.list_open_for_pod_reconciliation(threshold)

      assert id == old_open.id
    end

    test "list_open_for_pod_reconciliation/1 returns oldest first so a capped batch drains the worst leaks" do
      account = account_fixture()
      now = DateTime.utc_now()

      newer = session_fixture(account, pod_name: "pod-newer", started_at: DateTime.add(now, -3600, :second))
      oldest = session_fixture(account, pod_name: "pod-oldest", started_at: DateTime.add(now, -5 * 86_400, :second))

      assert [%{id: first}, %{id: second}] =
               RunnerSessions.list_open_for_pod_reconciliation(DateTime.add(now, -900, :second))

      assert first == oldest.id
      assert second == newer.id
    end

    test "close_pod_missing/3 closes a fresh orphan at now" do
      account = account_fixture()
      now = DateTime.utc_now()

      session =
        session_fixture(account,
          pod_name: "pod-fresh-orphan",
          started_at: DateTime.add(now, -1800, :second)
        )

      assert :ok = RunnerSessions.close_pod_missing(session.id, now)
      assert DateTime.compare(Repo.reload!(session).ended_at, now) == :eq
    end

    test "close_pod_missing/3 closes a long-leaked session at the billing clamp" do
      # The row was already charged against `started_at + 6h`, so
      # materialising that instant is billing-neutral — it only stops the
      # session counting as an occupied host.
      account = account_fixture()
      now = DateTime.utc_now()
      started_at = DateTime.add(now, -3 * 24 * 3600, :second)

      session = session_fixture(account, pod_name: "pod-ancient-orphan", started_at: started_at)

      assert :ok = RunnerSessions.close_pod_missing(session.id, now)

      expected = DateTime.add(started_at, Billing.max_session_lifetime_seconds(), :second)
      assert DateTime.compare(Repo.reload!(session).ended_at, expected) == :eq
    end

    test "close_pod_missing/3 loses to an accurate close that landed first" do
      account = account_fixture()
      now = DateTime.utc_now()
      accurate_close = DateTime.add(now, -300, :second)

      session =
        session_fixture(account,
          pod_name: "pod-raced",
          started_at: DateTime.add(now, -1800, :second)
        )

      {:ok, _} = RunnerSessions.close_by_pod_name("pod-raced", accurate_close)

      assert {:error, :stale_session} = RunnerSessions.close_pod_missing(session.id, now)
      assert DateTime.compare(Repo.reload!(session).ended_at, accurate_close) == :eq
    end

    test "close_pod_missing/3 closes at the job's real completion when one was resolved" do
      # Closing at the clamp would bill six hours for a job that ran for
      # five minutes; closing at `now` would bill the reaper's own
      # detection delay. Neither is what the customer used.
      account = account_fixture()
      now = DateTime.utc_now()
      started_at = DateTime.add(now, -1800, :second)
      completed_at = DateTime.add(started_at, 300, :second)

      session = session_fixture(account, pod_name: "pod-real-end", started_at: started_at)

      assert :ok = RunnerSessions.close_pod_missing(session.id, now, completed_at: completed_at)
      assert DateTime.compare(Repo.reload!(session).ended_at, completed_at) == :eq
    end

    test "close_pod_missing/3 never lets a late completion extend past now" do
      account = account_fixture()
      now = DateTime.utc_now()
      bogus_future = DateTime.add(now, 3600, :second)

      session =
        session_fixture(account,
          pod_name: "pod-future-completion",
          started_at: DateTime.add(now, -1800, :second)
        )

      assert :ok = RunnerSessions.close_pod_missing(session.id, now, completed_at: bogus_future)
      assert DateTime.compare(Repo.reload!(session).ended_at, now) == :eq
    end

    test "close_pod_missing/3 still honours the six-hour bound" do
      account = account_fixture()
      now = DateTime.utc_now()
      started_at = DateTime.add(now, -3 * 24 * 3600, :second)
      # A job GitHub reported as running for a day: the safety bound
      # outranks it, same as it does for the no-completion path.
      completed_at = DateTime.add(started_at, 24 * 3600, :second)

      session = session_fixture(account, pod_name: "pod-overlong", started_at: started_at)

      assert :ok = RunnerSessions.close_pod_missing(session.id, now, completed_at: completed_at)

      expected = DateTime.add(started_at, Billing.max_session_lifetime_seconds(), :second)
      assert DateTime.compare(Repo.reload!(session).ended_at, expected) == :eq
    end

    test "close_pod_missing/3 floors an inverted interval at started_at" do
      # GitHub's clock and ours can disagree. Writing a completion that
      # precedes `started_at` would give the billing query negative time.
      account = account_fixture()
      now = DateTime.utc_now()
      started_at = DateTime.add(now, -1800, :second)
      skewed = DateTime.add(started_at, -120, :second)

      session = session_fixture(account, pod_name: "pod-clock-skew", started_at: started_at)

      assert :ok = RunnerSessions.close_pod_missing(session.id, now, completed_at: skewed)

      ended_at = Repo.reload!(session).ended_at
      assert DateTime.compare(ended_at, started_at) == :eq
      assert DateTime.compare(ended_at, session.started_at) != :lt
    end

    test "close_pod_missing/3 is idempotent — a second close cannot move ended_at forward" do
      account = account_fixture()
      now = DateTime.utc_now()
      session = session_fixture(account, pod_name: "pod-twice", started_at: DateTime.add(now, -1800, :second))

      assert :ok = RunnerSessions.close_pod_missing(session.id, now)
      first_close = Repo.reload!(session).ended_at

      assert {:error, :stale_session} =
               RunnerSessions.close_pod_missing(session.id, DateTime.add(now, 600, :second))

      assert DateTime.compare(Repo.reload!(session).ended_at, first_close) == :eq
    end
  end
end
