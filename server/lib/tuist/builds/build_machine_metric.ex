defmodule Tuist.Builds.BuildMachineMetric do
  @moduledoc """
  Schema for machine metrics collected during builds.
  Used for both Xcode builds (via build_run_id) and Gradle builds (via gradle_build_id).
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "build_machine_metrics" do
    field :build_run_id, Ch, type: "Nullable(UUID)"
    field :gradle_build_id, Ch, type: "Nullable(UUID)"
    field :timestamp, Ch, type: "Float64"
    field :cpu_usage_percent, Ch, type: "Float32"
    field :memory_used_bytes, Ch, type: "Int64"
    field :memory_total_bytes, Ch, type: "Int64"
    field :network_bytes_in, Ch, type: "Int64"
    field :network_bytes_out, Ch, type: "Int64"
    field :disk_bytes_read, Ch, type: "Int64"
    field :disk_bytes_written, Ch, type: "Int64"
    field :inserted_at, :naive_datetime
  end
end
