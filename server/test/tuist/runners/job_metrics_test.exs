defmodule Tuist.Runners.JobMetricsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runners.JobMetrics

  defp sample(timestamp, attrs \\ %{}) do
    Map.merge(
      %{
        timestamp: timestamp,
        cpu_usage_percent: 40.0,
        cpu_iowait_percent: 1.5,
        memory_used_bytes: 7_516_192_768,
        memory_total_bytes: 15_032_385_536,
        network_bytes_in: 10_485_760,
        network_bytes_out: 5_242_880,
        disk_used_bytes: 48_318_382_080,
        disk_total_bytes: 68_719_476_736
      },
      attrs
    )
  end

  describe "record/3" do
    test "is a no-op on an empty sample list" do
      assert :ok = JobMetrics.record(910_000, 42, [])
      assert JobMetrics.list_for_job(910_000) == []
    end

    test "persists samples in time order with every field" do
      :ok =
        JobMetrics.record(910_001, 42, [
          sample(1_750_000_010.0, %{cpu_usage_percent: 90.0}),
          sample(1_750_000_005.0, %{cpu_usage_percent: 30.0})
        ])

      assert [
               %{timestamp: 1_750_000_005.0, cpu_usage_percent: cpu_first},
               %{
                 timestamp: 1_750_000_010.0,
                 cpu_usage_percent: cpu_second,
                 memory_used_bytes: 7_516_192_768,
                 disk_total_bytes: 68_719_476_736
               }
             ] = JobMetrics.list_for_job(910_001)

      assert_in_delta cpu_first, 30.0, 0.01
      assert_in_delta cpu_second, 90.0, 0.01
    end

    test "defaults omitted metric fields to zero" do
      :ok = JobMetrics.record(910_002, 42, [%{timestamp: 1_750_000_000.0, cpu_usage_percent: 12.0}])

      assert [
               %{
                 cpu_iowait_percent: iowait,
                 memory_used_bytes: 0,
                 disk_total_bytes: 0,
                 network_bytes_in: 0
               }
             ] = JobMetrics.list_for_job(910_002)

      assert_in_delta iowait, 0.0, 0.01
    end

    test "collapses a redelivered batch on the (workflow_job_id, timestamp) RMT key" do
      :ok = JobMetrics.record(910_003, 42, [sample(1_750_000_000.0, %{cpu_usage_percent: 10.0})])
      :ok = JobMetrics.record(910_003, 42, [sample(1_750_000_000.0, %{cpu_usage_percent: 80.0})])

      assert [%{timestamp: 1_750_000_000.0, cpu_usage_percent: cpu}] = JobMetrics.list_for_job(910_003)
      assert_in_delta cpu, 80.0, 0.01
    end
  end

  describe "list_for_job/1" do
    test "returns an empty list when no samples have been recorded" do
      assert JobMetrics.list_for_job(910_004) == []
    end

    test "scopes to the requested workflow_job_id" do
      :ok = JobMetrics.record(910_005, 42, [sample(1_750_000_000.0)])
      :ok = JobMetrics.record(910_006, 42, [sample(1_750_000_000.0)])

      assert [%{timestamp: 1_750_000_000.0}] = JobMetrics.list_for_job(910_005)
      assert [%{timestamp: 1_750_000_000.0}] = JobMetrics.list_for_job(910_006)
    end
  end
end
