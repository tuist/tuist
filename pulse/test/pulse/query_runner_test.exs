defmodule Pulse.QueryRunnerTest do
  use Pulse.Test.Case, async: true

  alias Pulse.QueryRunner
  alias Pulse.Runtime.Task

  test "tenant admission is shared across query classes and released after workers finish" do
    caller = self()
    supervisor = start_supervised!({Task.Supervisor, name: __MODULE__.Callers})

    workers =
      for class <- [:promql, :logql] do
        {:ok, _pid} =
          Task.Supervisor.start_child(supervisor, fn ->
            result =
              QueryRunner.run("shared", class, fn _deadline ->
                send(caller, {:started, self()})
                receive do: (:release -> {:ok, class})
              end)

            send(caller, {:finished, result})
          end)

        # Admission happens in supervised tasks; allow for a loaded async suite.
        assert_receive {:started, worker}, 5_000
        worker
      end

    assert {:error, :query_overloaded} = QueryRunner.run("shared", :raw, fn _ -> {:ok, :unexpected} end)
    assert Pulse.Metrics.render() =~ "pulse_query_occupied_slots 2\n"
    # Saturation for autoscaling: both workers hold interactive node slots.
    metrics = Pulse.Metrics.render()
    assert metrics =~ "pulse_query_inflight 2\n"
    assert metrics =~ "pulse_query_max_concurrent 3\n"
    assert Pulse.SelfMetrics.render() =~ ~s(pulse_admission_rejections_total{layer="query",reason="tenant"} 1\n)
    assert {:ok, :other} = QueryRunner.run("other", :raw, fn _ -> {:ok, :other} end)

    for pid <- workers do
      ref = Process.monitor(pid)
      send(pid, :release)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    assert_receive {:finished, {:ok, :promql}}
    assert_receive {:finished, {:ok, :logql}}
    assert {:ok, :released} = QueryRunner.run("shared", :raw, fn _ -> {:ok, :released} end)
  end

  test "with a queue, a query beyond the tenant's slots waits for one instead of being refused" do
    Pulse.Runtime.put_env(
      :pulse,
      QueryRunner,
      Keyword.put(Pulse.Runtime.get_env(:pulse, QueryRunner, []), :queue_ms, 4_000)
    )

    caller = self()
    supervisor = start_supervised!({Task.Supervisor, name: __MODULE__.Queued})

    [first, _second] =
      for n <- 1..2 do
        {:ok, _} =
          Task.Supervisor.start_child(supervisor, fn ->
            QueryRunner.run("queued", :promql, fn _ ->
              send(caller, {:holding, n, self()})
              receive do: (:release -> {:ok, n})
            end)
          end)

        assert_receive {:holding, ^n, worker}, 5_000
        worker
      end

    queued = Task.async(fn -> QueryRunner.run("queued", :promql, fn _ -> {:ok, :queued} end) end)
    refute Task.yield(queued, 200)
    send(first, :release)
    assert {:ok, :queued} = Task.await(queued, 5_000)
  end

  test "the limit a worker hit is reported to the calling process" do
    assert {:error, :query_scan_limit} =
             QueryRunner.run("limits", :promql, fn _ ->
               Pulse.QueryLimit.exceeded(:max_scan_segments, 1024, 3100, :visited)
             end)

    assert %{limit: :max_scan_segments, maximum: 1024, observed: 3100} = Pulse.QueryLimit.take()

    assert {:ok, :fine} = QueryRunner.run("limits", :promql, fn _ -> {:ok, :fine} end)
    assert Pulse.QueryLimit.take() == nil
  end
end
