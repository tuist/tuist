defmodule Tuist.MachineMetrics do
  @moduledoc """
  Shared module for machine metrics operations.
  Handles both Xcode and Gradle build metrics.
  """

  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.IngestRepo

  def create_machine_metrics(metrics_list, opts \\ []) when is_list(metrics_list) do
    build_run_id = Keyword.get(opts, :build_run_id)
    gradle_build_id = Keyword.get(opts, :gradle_build_id)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    entries =
      Enum.map(metrics_list, fn metric ->
        %{
          build_run_id: build_run_id,
          gradle_build_id: gradle_build_id,
          timestamp: metric.timestamp,
          cpu_usage_percent: metric.cpu_usage_percent,
          memory_used_bytes: metric.memory_used_bytes,
          memory_total_bytes: metric.memory_total_bytes,
          network_bytes_in: metric.network_bytes_in,
          network_bytes_out: metric.network_bytes_out,
          disk_bytes_read: metric.disk_bytes_read,
          disk_bytes_written: metric.disk_bytes_written,
          inserted_at: now
        }
      end)

    if Enum.empty?(entries) do
      :ok
    else
      IngestRepo.insert_all(BuildMachineMetric, entries)
      :ok
    end
  end

end
