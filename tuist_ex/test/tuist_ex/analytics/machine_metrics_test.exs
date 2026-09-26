defmodule TuistEx.Analytics.MachineMetricsTest do
  use ExUnit.Case, async: false

  alias TuistEx.Analytics.MachineMetrics

  test "sample/0 returns the fields the server persists" do
    sample = MachineMetrics.sample(fn -> 1_700_000_000.0 end)

    assert sample.timestamp == 1_700_000_000.0
    assert is_number(sample.cpu_usage_percent)
    assert is_integer(sample.memory_used_bytes)
    assert is_integer(sample.memory_total_bytes)
    assert sample.network_bytes_in == 0
    assert sample.network_bytes_out == 0
    assert sample.disk_bytes_read == 0
    assert sample.disk_bytes_written == 0
  end

  test "the sampler emits periodic samples to a function sink" do
    parent = self()
    sink = fn sample -> send(parent, {:sampled, sample}) end

    {:ok, pid} = MachineMetrics.start_link(sink: sink, interval_ms: 10)
    assert_receive {:sampled, _sample}, 500
    assert_receive {:sampled, _sample}, 500

    MachineMetrics.stop(pid)
  end

  test "the sampler emits samples to a pid sink" do
    {:ok, pid} = MachineMetrics.start_link(sink: self(), interval_ms: 10)
    assert_receive {:machine_metric, sample}, 500
    assert is_map(sample)

    MachineMetrics.stop(pid)
  end
end
