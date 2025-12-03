defmodule Tuist.CI.JobMetric do
  @moduledoc """
  A job metric represents a single metric data point from a CI job run.
  This is a ClickHouse entity that stores CI job metrics data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "ci_job_metrics" do
    field :job_run_id, Ecto.UUID

    field :metric_type,
          Ch,
          type:
            "Enum8('cpu_percent' = 0, 'memory_percent' = 1, 'network_bytes' = 2, 'cpu_io_wait_percent' = 3, 'storage_percent' = 4)"

    field :timestamp, Ch, type: "DateTime64(6)"
    field :value, Ch, type: "Float64"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(job_metric, attrs) do
    job_metric
    |> cast(attrs, [
      :id,
      :job_run_id,
      :metric_type,
      :timestamp,
      :value,
      :inserted_at
    ])
    |> validate_required([
      :id,
      :job_run_id,
      :metric_type,
      :timestamp,
      :value
    ])
  end
end
