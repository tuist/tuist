defmodule Tuist.MachineMetricsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.MachineMetrics

  @zero_uuid "00000000-0000-0000-0000-000000000000"

  defp sample_metrics do
    [
      %{
        timestamp_offset_ms: 1000,
        cpu_usage_percent: 45.5,
        memory_used_bytes: 8_000_000_000,
        memory_total_bytes: 16_000_000_000,
        network_bytes_in: 1_000_000,
        network_bytes_out: 500_000,
        disk_bytes_read: 2_000_000,
        disk_bytes_written: 1_500_000
      },
      %{
        timestamp_offset_ms: 2000,
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
    test "inserts metrics with build_run_id" do
      build_run_id = UUIDv7.generate()

      assert :ok = MachineMetrics.create_machine_metrics(sample_metrics(), build_run_id: build_run_id)

      metrics = ClickHouseRepo.all(from(m in BuildMachineMetric, where: m.build_run_id == ^build_run_id))
      assert length(metrics) == 2

      first = Enum.find(metrics, &(&1.timestamp_offset_ms == 1000))
      assert_in_delta first.cpu_usage_percent, 45.5, 0.01
      assert first.memory_used_bytes == 8_000_000_000
      assert first.memory_total_bytes == 16_000_000_000
      assert first.network_bytes_in == 1_000_000
      assert first.network_bytes_out == 500_000
      assert first.disk_bytes_read == 2_000_000
      assert first.disk_bytes_written == 1_500_000
      assert first.gradle_build_id == @zero_uuid
    end

    test "inserts metrics with gradle_build_id" do
      gradle_build_id = UUIDv7.generate()

      assert :ok = MachineMetrics.create_machine_metrics(sample_metrics(), gradle_build_id: gradle_build_id)

      metrics = ClickHouseRepo.all(from(m in BuildMachineMetric, where: m.gradle_build_id == ^gradle_build_id))
      assert length(metrics) == 2

      first = Enum.find(metrics, &(&1.timestamp_offset_ms == 1000))
      assert first.build_run_id == @zero_uuid
    end

    test "returns :ok for empty list without inserting" do
      assert :ok = MachineMetrics.create_machine_metrics([])
    end

    test "uses zero UUID when no IDs are provided" do
      expect(IngestRepo, :insert_all, fn BuildMachineMetric, entries ->
        assert length(entries) == 1
        entry = hd(entries)
        assert entry.build_run_id == @zero_uuid
        assert entry.gradle_build_id == @zero_uuid
        {1, nil}
      end)

      MachineMetrics.create_machine_metrics([hd(sample_metrics())])
    end
  end

  describe "get_machine_metrics_by_build_run_id/1" do
    test "returns metrics ordered by timestamp_offset_ms" do
      build_run_id = UUIDv7.generate()
      MachineMetrics.create_machine_metrics(sample_metrics(), build_run_id: build_run_id)

      metrics = MachineMetrics.get_machine_metrics_by_build_run_id(build_run_id)
      assert length(metrics) == 2
      assert Enum.at(metrics, 0).timestamp_offset_ms == 1000
      assert Enum.at(metrics, 1).timestamp_offset_ms == 2000
    end

    test "returns empty list when no metrics exist" do
      assert [] == MachineMetrics.get_machine_metrics_by_build_run_id(UUIDv7.generate())
    end

    test "does not return metrics for other builds" do
      build_run_id = UUIDv7.generate()
      other_build_run_id = UUIDv7.generate()
      MachineMetrics.create_machine_metrics(sample_metrics(), build_run_id: build_run_id)

      assert [] == MachineMetrics.get_machine_metrics_by_build_run_id(other_build_run_id)
    end
  end

  describe "get_machine_metrics_by_gradle_build_id/1" do
    test "returns metrics ordered by timestamp_offset_ms" do
      gradle_build_id = UUIDv7.generate()
      MachineMetrics.create_machine_metrics(sample_metrics(), gradle_build_id: gradle_build_id)

      metrics = MachineMetrics.get_machine_metrics_by_gradle_build_id(gradle_build_id)
      assert length(metrics) == 2
      assert Enum.at(metrics, 0).timestamp_offset_ms == 1000
      assert Enum.at(metrics, 1).timestamp_offset_ms == 2000
    end

    test "returns empty list when no metrics exist" do
      assert [] == MachineMetrics.get_machine_metrics_by_gradle_build_id(UUIDv7.generate())
    end

    test "does not return metrics for other builds" do
      gradle_build_id = UUIDv7.generate()
      other_gradle_build_id = UUIDv7.generate()
      MachineMetrics.create_machine_metrics(sample_metrics(), gradle_build_id: gradle_build_id)

      assert [] == MachineMetrics.get_machine_metrics_by_gradle_build_id(other_gradle_build_id)
    end
  end
end
