defmodule Pulse.MemoryPressureTest do
  use Pulse.Test.Case, async: true

  import Bitwise, only: [<<<: 2]

  alias Pulse.MemoryPressure
  alias Pulse.QueryRunner

  test "pressure turns on at the high mark, off only below the low mark, and refuses interactive queries" do
    used = :counters.new(1, [])

    sample = fn bytes ->
      :counters.put(used, 1, bytes)
      pid = Pulse.Runtime.whereis(MemoryPressure)
      send(pid, :sample)
      _ = :sys.get_state(pid)
    end

    start_supervised!(
      {MemoryPressure,
       limit: 1000, high_percent: 85, hold_ms: 0, interval_ms: 3_600_000, usage: fn -> :counters.get(used, 1) end}
    )

    sample.(840)
    refute MemoryPressure.active?()
    assert {:ok, :ran} = QueryRunner.run("tenant", :logql, fn _ -> {:ok, :ran} end)

    sample.(850)
    assert MemoryPressure.active?()
    assert {840 + 10, 1000} == MemoryPressure.stats()
    assert {:error, :query_overloaded} = QueryRunner.run("tenant", :logql, fn _ -> {:ok, :unexpected} end)
    # Background evaluation keeps running; only interactive queries are shed.
    assert {:ok, :alert} = QueryRunner.run("tenant", :alerting, fn _ -> {:ok, :alert} end)
    assert Pulse.Metrics.render() =~ "pulse_memory_pressure 1\n"
    assert Pulse.SelfMetrics.render() =~ ~s(pulse_admission_rejections_total{layer="query",reason="memory"} 1\n)

    # Hysteresis: between the low (75%) and high marks the state holds.
    sample.(760)
    assert MemoryPressure.active?()
    # Off takes one sample below the low mark to start the hold, then the hold.
    sample.(749)
    sample.(749)
    refute MemoryPressure.active?()
    assert {:ok, :ran} = QueryRunner.run("tenant", :logql, fn _ -> {:ok, :ran} end)

    metrics = Pulse.SelfMetrics.render()
    assert metrics =~ ~s(pulse_memory_pressure_transitions_total{state="on"} 1\n)
    assert metrics =~ ~s(pulse_memory_pressure_transitions_total{state="off"} 1\n)
  end

  test "pressure stays on until memory has held below the low mark" do
    used = :counters.new(1, [])

    start_supervised!(
      {MemoryPressure, limit: 1000, hold_ms: 3_600_000, interval_ms: 3_600_000, usage: fn -> :counters.get(used, 1) end}
    )

    pid = Pulse.Runtime.whereis(MemoryPressure)

    for bytes <- [900, 100, 100, 100] do
      :counters.put(used, 1, bytes)
      send(pid, :sample)
      _ = :sys.get_state(pid)
    end

    assert MemoryPressure.active?()
  end

  test "without a known limit pressure is never reported" do
    start_supervised!({MemoryPressure, limit: nil, interval_ms: 3_600_000, usage: fn -> 1 <<< 40 end})
    _ = :sys.get_state(Pulse.Runtime.whereis(MemoryPressure))
    refute MemoryPressure.active?()
  end
end
