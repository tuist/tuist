defmodule Tuist.Oban.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Oban.PromExPlugin

  describe "execute_recent_terminal_metrics/0" do
    test "emits one telemetry event per (queue, state, worker) for jobs discarded inside the lookback window" do
      now = DateTime.utc_now()
      recent = DateTime.add(now, -5 * 60, :second)
      stale = DateTime.add(now, -90 * 60, :second)

      insert_job!(
        queue: "process_xcresult",
        worker: "Tuist.Tests.Workers.ProcessXcresultWorker",
        state: "discarded",
        discarded_at: recent
      )

      insert_job!(
        queue: "process_xcresult",
        worker: "Tuist.Tests.Workers.ProcessXcresultWorker",
        state: "discarded",
        discarded_at: recent
      )

      insert_job!(
        queue: "default",
        worker: "Tuist.Some.OtherWorker",
        state: "cancelled",
        cancelled_at: recent
      )

      # Outside the 30-minute window — must not be reported.
      insert_job!(
        queue: "process_xcresult",
        worker: "Tuist.Tests.Workers.ProcessXcresultWorker",
        state: "discarded",
        discarded_at: stale
      )

      # In flight — must not be reported.
      insert_job!(
        queue: "default",
        worker: "Tuist.Some.OtherWorker",
        state: "executing"
      )

      events =
        attach_capture([:prom_ex, :plugin, :oban, :jobs, :recent, :terminal, :count])

      try do
        PromExPlugin.execute_recent_terminal_metrics()
      after
        :telemetry.detach(events)
      end

      received = drain_telemetry()

      assert {%{count: 2},
              %{queue: "process_xcresult", state: "discarded", worker: "Tuist.Tests.Workers.ProcessXcresultWorker"}} in received

      assert {%{count: 1}, %{queue: "default", state: "cancelled", worker: "Tuist.Some.OtherWorker"}} in received
      assert length(received) == 2
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

  defp attach_capture(event_name) do
    test_pid = self()
    handler_id = {__MODULE__, System.unique_integer([:positive])}

    :telemetry.attach(
      handler_id,
      event_name,
      fn ^event_name, measurements, metadata, _ ->
        send(test_pid, {:telemetry, measurements, metadata})
      end,
      nil
    )

    handler_id
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
