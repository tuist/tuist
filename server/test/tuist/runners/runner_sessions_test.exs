defmodule Tuist.Runners.RunnerSessionsTest do
  use TuistTestSupport.Cases.DataCase

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
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
end
