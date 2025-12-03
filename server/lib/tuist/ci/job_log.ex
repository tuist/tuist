defmodule Tuist.CI.JobLog do
  @moduledoc """
  A job log represents a single log line from a CI job step.
  This is a ClickHouse entity that stores CI job log data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "ci_job_logs" do
    field :step_id, Ecto.UUID
    field :job_run_id, Ecto.UUID
    field :timestamp, Ch, type: "DateTime64(6)"
    field :message, :string
    field :stream, Ch, type: "Enum8('stdout' = 0, 'stderr' = 1)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(job_log, attrs) do
    job_log
    |> cast(attrs, [
      :id,
      :step_id,
      :job_run_id,
      :timestamp,
      :message,
      :stream,
      :inserted_at
    ])
    |> validate_required([
      :id,
      :step_id,
      :job_run_id,
      :timestamp,
      :message,
      :stream
    ])
  end
end
