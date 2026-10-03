defmodule TuistEx.Analytics.MachineMetricsTest do
  use ExUnit.Case, async: true

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

  # The samplers below are given what to report, so they start nothing that
  # belongs to the whole VM and can run next to each other.
  defp fake_sample(rates), do: Map.merge(%{timestamp: 1.0, cpu_usage_percent: 50.0}, rates)
  defp fake_counters, do: %{network: {1_000, 2_000}, disk: {3_000, 4_000}}

  defp sampler(sink) do
    start_supervised!(
      {MachineMetrics,
       sink: sink, interval_ms: 10, sample: &fake_sample/1, counters: &fake_counters/0}
    )
  end

  test "the sampler emits a first sample at once, then periodic ones, to a function sink" do
    parent = self()
    sink = fn sample -> send(parent, {:sampled, sample}) end

    pid = sampler(sink)
    # The first carries no throughput: that needs two counter readings.
    assert_receive {:sampled, first}, 5_000
    assert first == %{timestamp: 1.0, cpu_usage_percent: 50.0}
    # The counters did not move between readings, so the throughput is zero.
    assert_receive {:sampled, %{network_bytes_in: 0, disk_bytes_written: 0}}, 5_000

    MachineMetrics.stop(pid)
  end

  test "the sampler emits samples to a pid sink" do
    pid =
      start_supervised!({MachineMetrics, sink: self(), interval_ms: 10, sample: &fake_sample/1})

    assert_receive {:machine_metric, %{cpu_usage_percent: 50.0}}, 5_000

    MachineMetrics.stop(pid)
  end
end
