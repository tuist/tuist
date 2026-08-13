defmodule Tuist.Runners.Workers.OrphanedSessionsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Billing
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Workers.OrphanedSessionsWorker

  setup :verify_on_exit!

  defp session_fixture(account, attrs) do
    defaults = %{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "fleet-orphans",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      # Well past the worker's grace period so the row is a candidate
      # unless a test deliberately makes it recent.
      started_at: DateTime.add(DateTime.utc_now(), -3, :hour),
      ended_at: nil,
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    Repo.insert!(struct(RunnerSession, Map.merge(defaults, Map.new(attrs))))
  end

  defp reload(session), do: Repo.get!(RunnerSession, session.id)

  describe "perform/1" do
    test "closes an orphaned session at the terminal completion of its job" do
      # The controller never reported the Pod stopped, so the row sat
      # open and billed against the six-hour clamp. GitHub's terminal
      # timestamp recovers the real window.
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -3, :hour)
      completed_at = DateTime.add(started_at, 94, :second)

      session = session_fixture(account, workflow_job_id: 94_218_433_307, started_at: started_at)

      expect(Jobs, :terminal_completions, fn ids ->
        assert ids == [94_218_433_307]
        %{94_218_433_307 => completed_at}
      end)

      assert :ok = OrphanedSessionsWorker.perform(%Oban.Job{})

      assert DateTime.compare(reload(session).ended_at, completed_at) == :eq
    end

    test "leaves a session open when its job has not reached a terminal state" do
      # Indistinguishable from a genuinely long build, and real
      # six-hour builds exist on these fleets. The billing clamp
      # covers it until the job-side workers drive it terminal.
      account = account_fixture()
      session = session_fixture(account, workflow_job_id: 94_245_504_882)

      expect(Jobs, :terminal_completions, fn _ids -> %{} end)

      assert :ok = OrphanedSessionsWorker.perform(%Oban.Job{})

      assert is_nil(reload(session).ended_at)
    end

    test "leaves a session open when its job completed inside the grace period" do
      # The controller's report lands within seconds and carries the
      # post-job cache and teardown tail. Intervening this early would
      # steal the accurate close and drop that tail.
      account = account_fixture()
      session = session_fixture(account, workflow_job_id: 94_284_875_086)

      expect(Jobs, :terminal_completions, fn _ids ->
        %{94_284_875_086 => DateTime.add(DateTime.utc_now(), -30, :second)}
      end)

      assert :ok = OrphanedSessionsWorker.perform(%Oban.Job{})

      assert is_nil(reload(session).ended_at)
    end

    test "ignores sessions younger than the grace period without querying ClickHouse" do
      account = account_fixture()

      session =
        session_fixture(account, started_at: DateTime.add(DateTime.utc_now(), -60, :second))

      reject(&Jobs.terminal_completions/1)

      assert :ok = OrphanedSessionsWorker.perform(%Oban.Job{})

      assert is_nil(reload(session).ended_at)
    end

    test "resolves against the job GitHub proved ran on the runner" do
      # `executed_workflow_job_id` is ground truth when the runner
      # picked up a different job than it was dispatched for; that
      # job's completion is what released the Pod.
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -2, :hour)
      completed_at = DateTime.add(started_at, 12, :minute)

      session =
        session_fixture(account,
          workflow_job_id: 111,
          executed_workflow_job_id: 222,
          started_at: started_at
        )

      expect(Jobs, :terminal_completions, fn ids ->
        assert ids == [222]
        %{222 => completed_at}
      end)

      assert :ok = OrphanedSessionsWorker.perform(%Oban.Job{})

      assert DateTime.compare(reload(session).ended_at, completed_at) == :eq
    end

    test "floors the close at started_at when the job completed before the claim" do
      # Clock skew against GitHub, or a `completed_at` belonging to an
      # earlier attempt on the same runner. Writing it verbatim would
      # invert the interval and bill negative time.
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -2, :hour)

      session = session_fixture(account, workflow_job_id: 333, started_at: started_at)

      expect(Jobs, :terminal_completions, fn _ids ->
        %{333 => DateTime.add(started_at, -5, :minute)}
      end)

      assert :ok = OrphanedSessionsWorker.perform(%Oban.Job{})

      assert DateTime.compare(reload(session).ended_at, started_at) == :eq
    end

    test "does not reopen or extend an already closed session" do
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -3, :hour)
      ended_at = DateTime.add(started_at, 5, :minute)

      session = session_fixture(account, workflow_job_id: 444, started_at: started_at, ended_at: ended_at)

      reject(&Jobs.terminal_completions/1)

      assert :ok = OrphanedSessionsWorker.perform(%Oban.Job{})

      assert DateTime.compare(reload(session).ended_at, ended_at) == :eq
    end

    test "is a no-op when nothing is open past the grace period" do
      reject(&Jobs.terminal_completions/1)

      assert :ok = OrphanedSessionsWorker.perform(%Oban.Job{})
    end
  end

  describe "billing recovery" do
    test "replaces the clamped safety bound with the real billed window" do
      # The regression this worker exists for. A Pod whose `stopped`
      # event never arrived billed `@max_session_lifetime_seconds`
      # against a job that really ran for 94 seconds — observed in
      # production at 360 billed minutes per orphan, 78% of one
      # customer's daily total.
      account = account_fixture()
      # Older than the clamp, so the open row bills the safety bound
      # rather than simply `now()`.
      started_at = DateTime.add(DateTime.utc_now(), -10, :hour)
      completed_at = DateTime.add(started_at, 94, :second)

      session_fixture(account, workflow_job_id: 94_218_433_307, started_at: started_at)

      period_start = DateTime.add(started_at, -1, :hour)
      period_end = DateTime.add(DateTime.utc_now(), 1, :hour)

      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 6 * 60 * 60 * 1_000

      expect(Jobs, :terminal_completions, fn _ids -> %{94_218_433_307 => completed_at} end)

      assert :ok = OrphanedSessionsWorker.perform(%Oban.Job{})

      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 94 * 1_000
    end
  end

  describe "close_by_id/2" do
    test "keeps the earlier end when a close races in with a later timestamp" do
      account = account_fixture()
      started_at = DateTime.add(DateTime.utc_now(), -3, :hour)
      ended_at = DateTime.add(started_at, 4, :minute)

      session = session_fixture(account, started_at: started_at, ended_at: ended_at)

      assert {:ok, updated} =
               RunnerSessions.close_by_id(session.id, DateTime.add(started_at, 90, :minute))

      assert DateTime.compare(updated.ended_at, ended_at) == :eq
    end

    test "returns :no_open_session for an unknown id" do
      assert {:ok, :no_open_session} = RunnerSessions.close_by_id(-1, DateTime.utc_now())
    end
  end
end
