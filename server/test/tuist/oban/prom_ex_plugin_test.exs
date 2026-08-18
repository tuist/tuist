defmodule Tuist.Oban.PromExPluginTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Oban.PromExPlugin

  @length_event [:prom_ex, :plugin, :oban, :queue, :length, :count]
  @age_event [:prom_ex, :plugin, :oban, :queue, :oldest, :available, :age, :seconds]

  setup do
    handler_id = make_ref()
    on_exit(fn -> :telemetry.detach(handler_id) end)
    {:ok, handler_id: handler_id}
  end

  defp attach_collector(handler_id, event_name) do
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        event_name,
        fn name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, name, measurements, metadata})
        end,
        nil
      )
  end

  defp insert_job(queue, state, scheduled_at) do
    Tuist.Repo.insert!(%Oban.Job{
      worker: "Tuist.TestWorker",
      queue: queue,
      state: state,
      args: %{},
      scheduled_at: scheduled_at
    })
  end

  defp collect(event) do
    receive do
      {:telemetry_event, ^event, measurements, metadata} -> [{measurements, metadata} | collect(event)]
    after
      0 -> []
    end
  end

  describe "execute_queue_metrics/0" do
    test "reports the age of the oldest available job per queue", %{handler_id: handler_id} do
      attach_collector(handler_id, @age_event)

      insert_job("process_xcresult", "available", DateTime.add(DateTime.utc_now(), -3600, :second))
      insert_job("process_xcresult", "available", DateTime.add(DateTime.utc_now(), -60, :second))

      PromExPlugin.execute_queue_metrics()

      ages = collect(@age_event)
      assert {%{age_seconds: age}, _} = Enum.find(ages, fn {_, meta} -> meta.queue == "process_xcresult" end)
      assert_in_delta age, 3600, 30
    end

    test "reports zero for a queue with no available jobs", %{handler_id: handler_id} do
      attach_collector(handler_id, @age_event)

      insert_job("process_xcresult", "executing", DateTime.add(DateTime.utc_now(), -3600, :second))

      PromExPlugin.execute_queue_metrics()

      ages = collect(@age_event)
      assert {%{age_seconds: 0}, _} = Enum.find(ages, fn {_, meta} -> meta.queue == "process_xcresult" end)
    end

    test "ignores scheduled and retryable jobs whose scheduled_at is in the future", %{handler_id: handler_id} do
      attach_collector(handler_id, @age_event)

      insert_job("process_xcresult", "retryable", DateTime.add(DateTime.utc_now(), 300, :second))

      PromExPlugin.execute_queue_metrics()

      ages = collect(@age_event)
      assert {%{age_seconds: 0}, _} = Enum.find(ages, fn {_, meta} -> meta.queue == "process_xcresult" end)
    end

    test "emits a final zero for a queue that drained since the previous poll", %{handler_id: handler_id} do
      job = insert_job("process_xcresult", "available", DateTime.add(DateTime.utc_now(), -3600, :second))

      PromExPlugin.execute_queue_metrics()

      Tuist.Repo.delete!(job)
      attach_collector(handler_id, @age_event)

      PromExPlugin.execute_queue_metrics()

      ages = collect(@age_event)
      assert {%{age_seconds: 0}, _} = Enum.find(ages, fn {_, meta} -> meta.queue == "process_xcresult" end)
    end

    test "still reports queue length per state", %{handler_id: handler_id} do
      attach_collector(handler_id, @length_event)

      insert_job("process_xcresult", "available", DateTime.utc_now())

      PromExPlugin.execute_queue_metrics()

      lengths = collect(@length_event)

      assert {%{count: 1}, _} =
               Enum.find(lengths, fn {_, meta} -> meta.queue == "process_xcresult" and meta.state == "available" end)
    end
  end
end
