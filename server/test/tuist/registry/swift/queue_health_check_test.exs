defmodule Tuist.Registry.Swift.QueueHealthCheckTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Registry.Swift.QueueHealthCheck
  alias Tuist.Repo

  setup :verify_on_exit!

  # `wedged_queue/1` accepts the same state shape `init/1` builds, so
  # every test constructs it via this helper and can override the two
  # bits it cares about — where the wall clock is, and how far back
  # the pod booted — without spinning up a GenServer.
  defp state(overrides) do
    defaults = %{
      check_interval: :timer.minutes(1),
      grace_period: :timer.minutes(15),
      stuck_after: :timer.minutes(10),
      queues: ["swift_registry_sync"],
      halt: fn -> :halted end,
      now: fn -> ~U[2026-01-01 12:00:00Z] end,
      boot_at: ~U[2026-01-01 11:00:00Z]
    }

    Map.merge(defaults, Map.new(overrides))
  end

  describe "wedged_queue/1 — grace period" do
    test "returns :ok during the grace window even when a stuck job would normally trip" do
      # Pod has been up for 5 minutes; grace period is 15 minutes. Even
      # if the queue is technically stuck we must not restart a pod
      # that hasn't finished warming its producer supervisor.
      state =
        state(
          now: fn -> ~U[2026-01-01 11:05:00Z] end,
          boot_at: ~U[2026-01-01 11:00:00Z]
        )

      # Even though we set up a query result that would ordinarily
      # trip, the health check should never call the DB during grace.
      expect(Repo, :query, 0, fn _q, _params -> flunk("query fired during grace") end)

      assert :ok == QueueHealthCheck.wedged_queue(state)
    end
  end

  describe "wedged_queue/1 — no stuck jobs" do
    test "returns :ok when no available jobs exceed the stuck_after threshold" do
      state = state([])

      # `MIN(COALESCE(scheduled_at, inserted_at))` returns nil when the
      # subquery matched no rows, which means every available job is
      # newer than the threshold.
      expect(Repo, :query, fn _q, _params ->
        {:ok, %{rows: [[nil, ~U[2026-01-01 11:55:00Z]]]}}
      end)

      assert :ok == QueueHealthCheck.wedged_queue(state)
    end
  end

  describe "wedged_queue/1 — producer proven healthy" do
    test "returns :ok when a job has been attempted after the oldest stuck job appeared" do
      state = state([])

      # Oldest available job dates from 11:30, and the queue's most
      # recent attempt is at 11:45. The producer picked up something
      # after the "stuck" job showed up, so the stuck job just hasn't
      # been reached yet. Do not restart.
      expect(Repo, :query, fn _q, _params ->
        {:ok, %{rows: [[~U[2026-01-01 11:30:00Z], ~U[2026-01-01 11:45:00Z]]]}}
      end)

      assert :ok == QueueHealthCheck.wedged_queue(state)
    end
  end

  describe "wedged_queue/1 — producer wedged" do
    test "returns {:wedged, queue, stuck_since} when queue has an old available job and the last attempt predates it" do
      state = state([])

      # Oldest available job at 11:30, most recent attempt at 11:20.
      # No pickup after the stuck job appeared → the producer is
      # not draining.
      expect(Repo, :query, fn _q, _params ->
        {:ok, %{rows: [[~U[2026-01-01 11:30:00Z], ~U[2026-01-01 11:20:00Z]]]}}
      end)

      assert {:wedged, "swift_registry_sync", ~U[2026-01-01 11:30:00Z]} ==
               QueueHealthCheck.wedged_queue(state)
    end

    test "returns {:wedged, ...} when queue has a stuck available job and no attempts have ever been made" do
      state = state([])

      expect(Repo, :query, fn _q, _params ->
        {:ok, %{rows: [[~U[2026-01-01 11:30:00Z], nil]]}}
      end)

      assert {:wedged, "swift_registry_sync", ~U[2026-01-01 11:30:00Z]} ==
               QueueHealthCheck.wedged_queue(state)
    end
  end

  describe "wedged_queue/1 — multiple queues" do
    test "checks each queue in order and returns the first wedged one" do
      state = state(queues: ["swift_registry_sync", "swift_registry_release"])

      expect(Repo, :query, fn _q, [queue, _threshold] ->
        case queue do
          "swift_registry_sync" ->
            {:ok, %{rows: [[nil, ~U[2026-01-01 11:55:00Z]]]}}

          "swift_registry_release" ->
            {:ok, %{rows: [[~U[2026-01-01 11:30:00Z], ~U[2026-01-01 11:20:00Z]]]}}
        end
      end)

      assert {:wedged, "swift_registry_release", ~U[2026-01-01 11:30:00Z]} ==
               QueueHealthCheck.wedged_queue(state)
    end

    test "returns :ok when every queue is healthy" do
      state = state(queues: ["swift_registry_sync", "swift_registry_release"])

      expect(Repo, :query, 2, fn _q, _params ->
        {:ok, %{rows: [[nil, ~U[2026-01-01 11:55:00Z]]]}}
      end)

      assert :ok == QueueHealthCheck.wedged_queue(state)
    end
  end

  describe "wedged_queue/1 — DB errors" do
    test "returns :ok when the health-check query itself fails, and lets the next tick retry" do
      # A DB error on the check is a poor signal to halt on — the
      # cluster could be momentarily reachable-but-slow for reasons
      # unrelated to the sync queue's producer. Skip this tick.
      state = state([])

      expect(Repo, :query, fn _q, _params -> {:error, :timeout} end)

      assert :ok == QueueHealthCheck.wedged_queue(state)
    end
  end
end
