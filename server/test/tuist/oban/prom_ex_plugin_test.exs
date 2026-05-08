defmodule Tuist.Oban.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Oban.PromExPlugin

  describe "execute_recent_state_metrics/0" do
    test "emits one telemetry event per (queue, state, worker), counting in-window rows for every tracked state" do
      now = DateTime.utc_now()
      recent = DateTime.add(now, -5 * 60, :second)
      stale = DateTime.add(now, -90 * 60, :second)

      insert_job!(
        queue: "process_xcresult",
        worker: "Tuist.Tests.Workers.ProcessXcresultWorker",
        state: "discarded",
        attempted_at: recent,
        discarded_at: recent
      )

      insert_job!(
        queue: "process_xcresult",
        worker: "Tuist.Tests.Workers.ProcessXcresultWorker",
        state: "discarded",
        attempted_at: recent,
        discarded_at: recent
      )

      insert_job!(
        queue: "default",
        worker: "Tuist.Some.OtherWorker",
        state: "cancelled",
        cancelled_at: recent
      )

      insert_job!(
        queue: "default",
        worker: "Tuist.Some.OtherWorker",
        state: "completed",
        attempted_at: recent,
        completed_at: recent
      )

      insert_job!(
        queue: "default",
        worker: "Tuist.Some.OtherWorker",
        state: "retryable",
        attempted_at: recent
      )

      # Aged out — keeps its labelset but emits zero, so the gauge clears.
      insert_job!(
        queue: "process_xcresult",
        worker: "Tuist.Tests.Workers.OldWorker",
        state: "discarded",
        attempted_at: stale,
        discarded_at: stale
      )

      # In flight — not in the tracked states, so it shouldn't show up at all.
      insert_job!(
        queue: "default",
        worker: "Tuist.Some.OtherWorker",
        state: "executing",
        attempted_at: recent
      )

      received = capture_telemetry(&PromExPlugin.execute_recent_state_metrics/0)

      assert {%{count: 2},
              %{queue: "process_xcresult", state: "discarded", worker: "Tuist.Tests.Workers.ProcessXcresultWorker"}} in received

      assert {%{count: 1}, %{queue: "default", state: "cancelled", worker: "Tuist.Some.OtherWorker"}} in received

      assert {%{count: 1}, %{queue: "default", state: "completed", worker: "Tuist.Some.OtherWorker"}} in received

      assert {%{count: 1}, %{queue: "default", state: "retryable", worker: "Tuist.Some.OtherWorker"}} in received

      assert {%{count: 0}, %{queue: "process_xcresult", state: "discarded", worker: "Tuist.Tests.Workers.OldWorker"}} in received

      # 4 in-window labelsets + 1 aged-out (still emitted as zero).
      assert length(received) == 5

      # `executing` is not one of the tracked states, so no series for that worker/state combo.
      refute Enum.any?(received, fn {_, %{state: state}} -> state == "executing" end)
    end

    test "drops a previously-counted labelset to zero on the next poll once its row ages out of the window" do
      base = DateTime.utc_now()
      discarded_at = DateTime.add(base, -5 * 60, :second)

      insert_job!(
        queue: "process_xcresult",
        worker: "Tuist.Tests.Workers.ProcessXcresultWorker",
        state: "discarded",
        attempted_at: discarded_at,
        discarded_at: discarded_at
      )

      # First poll — wall-clock now. Discard is 5 minutes old → in window.
      stub(DateTime, :utc_now, fn -> base end)
      first = capture_telemetry(&PromExPlugin.execute_recent_state_metrics/0)

      assert {%{count: 1},
              %{queue: "process_xcresult", state: "discarded", worker: "Tuist.Tests.Workers.ProcessXcresultWorker"}} in first

      # Second poll — pretend we're 35 minutes later. Same row is now
      # outside the 30-minute window. Same labelset must still emit, with
      # count: 0, so the last_value gauge clears (and the alert resolves).
      later = DateTime.add(base, 35 * 60, :second)
      stub(DateTime, :utc_now, fn -> later end)
      second = capture_telemetry(&PromExPlugin.execute_recent_state_metrics/0)

      assert {%{count: 0},
              %{queue: "process_xcresult", state: "discarded", worker: "Tuist.Tests.Workers.ProcessXcresultWorker"}} in second
    end
  end

  defp insert_job!(attrs) do
    base = %{
      args: %{},
      attempt: 1,
      max_attempts: 1,
      inserted_at: DateTime.utc_now()
    }

    Tuist.Repo.insert!(struct(Oban.Job, Map.merge(base, Map.new(attrs))))
  end

  defp capture_telemetry(fun) do
    test_pid = self()
    event = [:prom_ex, :plugin, :oban, :jobs, :recent, :count]
    handler_id = {__MODULE__, System.unique_integer([:positive])}

    :telemetry.attach(
      handler_id,
      event,
      fn ^event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, measurements, metadata})
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end

    drain_telemetry()
  end

  defp drain_telemetry(acc \\ []) do
    receive do
      {:telemetry, measurements, metadata} ->
        drain_telemetry([{measurements, Map.take(metadata, [:queue, :state, :worker])} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
