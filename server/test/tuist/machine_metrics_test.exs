defmodule Tuist.MachineMetricsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  import Ecto.Query

  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.MachineMetrics

  @base_timestamp 1_741_500_000.0

  defp sample_metrics do
    [
      %{
        timestamp: @base_timestamp + 1.0,
        cpu_usage_percent: 45.5,
        memory_used_bytes: 8_000_000_000,
        memory_total_bytes: 16_000_000_000,
        network_bytes_in: 1_000_000,
        network_bytes_out: 500_000,
        disk_bytes_read: 2_000_000,
        disk_bytes_written: 1_500_000
      },
      %{
        timestamp: @base_timestamp + 2.0,
        cpu_usage_percent: 72.3,
        memory_used_bytes: 10_000_000_000,
        memory_total_bytes: 16_000_000_000,
        network_bytes_in: 2_000_000,
        network_bytes_out: 1_000_000,
        disk_bytes_read: 3_000_000,
        disk_bytes_written: 2_500_000
      }
    ]
  end

  describe "create_machine_metrics/2" do
    test "inserts metrics with build_run_id and stores timestamps" do
      build_run_id = UUIDv7.generate()

      assert :ok = MachineMetrics.create_machine_metrics(sample_metrics(), build_run_id: build_run_id)

      metrics = ClickHouseRepo.all(from(m in BuildMachineMetric, where: m.build_run_id == ^build_run_id))
      assert length(metrics) == 2

      first = Enum.find(metrics, &(&1.timestamp == @base_timestamp + 1.0))
      assert first != nil
      assert_in_delta first.cpu_usage_percent, 45.5, 0.01
      assert first.memory_used_bytes == 8_000_000_000
      assert first.memory_total_bytes == 16_000_000_000
      assert first.network_bytes_in == 1_000_000
      assert first.network_bytes_out == 500_000
      assert first.disk_bytes_read == 2_000_000
      assert first.disk_bytes_written == 1_500_000
      assert first.gradle_build_id == nil

      second = Enum.find(metrics, &(&1.timestamp == @base_timestamp + 2.0))
      assert second != nil
    end

    test "inserts metrics with gradle_build_id" do
      gradle_build_id = UUIDv7.generate()

      assert :ok = MachineMetrics.create_machine_metrics(sample_metrics(), gradle_build_id: gradle_build_id)

      metrics = ClickHouseRepo.all(from(m in BuildMachineMetric, where: m.gradle_build_id == ^gradle_build_id))
      assert length(metrics) == 2

      first = Enum.find(metrics, &(&1.timestamp == @base_timestamp + 1.0))
      assert first.build_run_id == nil
    end

    test "returns :ok for empty list without inserting" do
      assert :ok = MachineMetrics.create_machine_metrics([])
    end

    test "uses nil when no IDs are provided" do
      expect(IngestRepo, :insert_all, fn BuildMachineMetric, entries ->
        assert length(entries) == 1
        entry = hd(entries)
        assert entry.build_run_id == nil
        assert entry.gradle_build_id == nil
        assert entry.timestamp == @base_timestamp + 1.0
        {1, nil}
      end)

      MachineMetrics.create_machine_metrics([hd(sample_metrics())])
    end
  end
end
