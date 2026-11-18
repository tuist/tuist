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

  describe "out_of_memory/1" do
    test "summarizes the job's kills and names the process killed last" do
      # A redelivered earlier batch can be the newest write, so the last
      # sample in time order is not guaranteed to carry the total.
      :ok =
        JobMetrics.record(910_007, 42, [
          sample(1_750_000_000.0, %{oom_kill_count: 0}),
          sample(1_750_000_015.0, %{
            oom_kill_count: 1,
            oom_victim_process: "node",
            oom_victim_memory_bytes: 1_000,
            oom_victim_container: "web",
            oom_victim_image: "node:22"
          }),
          sample(1_750_000_030.0, %{
            oom_kill_count: 2,
            oom_victim_process: "java",
            oom_victim_memory_bytes: 27_917_287_424,
            oom_victim_container: "gradle-build",
            oom_victim_image: "gradle:8-jdk21"
          }),
          sample(1_750_000_045.0, %{oom_kill_count: 1, oom_victim_process: "node", oom_victim_memory_bytes: 1_000})
        ])

      assert JobMetrics.out_of_memory(JobMetrics.list_for_job(910_007)) == %{
               count: 2,
               at: 1_750_000_015.0,
               victim: %{
                 process: "java",
                 memory_bytes: 27_917_287_424,
                 container: "gradle-build",
                 image: "gradle:8-jdk21"
               }
             }
    end

    test "reports kills without a victim, as on pools without the dind sidecar" do
      :ok = JobMetrics.record(910_008, 42, [sample(1_750_000_000.0, %{oom_kill_count: 3})])

      assert %{count: 3, victim: nil} = JobMetrics.out_of_memory(JobMetrics.list_for_job(910_008))
    end

    test "is nil for a job that killed nothing" do
      :ok = JobMetrics.record(910_009, 42, [sample(1_750_000_000.0)])

      assert JobMetrics.out_of_memory(JobMetrics.list_for_job(910_009)) == nil
      assert JobMetrics.out_of_memory([]) == nil
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

  describe "out_of_memory_description/1" do
    defp oom_description(count, victim), do: JobMetrics.out_of_memory_description(%{count: count, victim: victim})

    defp victim(attrs), do: Map.merge(%{process: "java", memory_bytes: 1_000_000_000, container: nil, image: nil}, attrs)

    test "gives JVM advice only when the process stopped was a JVM" do
      assert oom_description(1, victim(%{})) =~ "org.gradle.jvmargs"
      refute oom_description(1, victim(%{process: "node"})) =~ "JVM"
      refute oom_description(1, nil) =~ "JVM"
    end

    test "says where the process ran" do
      assert oom_description(1, victim(%{process: "node"})) =~
               "It stopped node, which was using 1.0 GB, outside any container."

      assert oom_description(1, victim(%{process: "cc1plus", container: "docker-build"})) =~
               "It stopped cc1plus, which was using 1.0 GB, in a Docker build step."

      assert oom_description(1, victim(%{container: "3f3f3f3f3f3f"})) =~ "in the container 3f3f3f3f3f3f."
    end

    test "explains a lost runner when the runner itself was stopped" do
      description = oom_description(1, victim(%{process: "Runner.Worker"}))
      assert description =~ "It stopped the GitHub runner itself (Runner.Worker), so GitHub reports"
      refute description =~ "A stopped process fails"
    end

    test "falls back to the general explanation without a victim" do
      assert oom_description(3, nil) ==
               "The runner's machine ran out of memory, and the system stopped 3 processes to free it. " <>
                 "A stopped process fails the step that started it; if it was the runner itself, GitHub reports that the runner lost communication. " <>
                 "Lower the memory your build uses, or use a runner with more memory."
    end
  end
end
