defmodule Tuist.CI.JobStep do
  @moduledoc """
  A job step represents a single step within a CI job run.
  This is a ClickHouse entity that stores CI job step data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "ci_job_steps" do
    field :job_run_id, Ecto.UUID
    field :step_number, Ch, type: "UInt16"
    field :step_name, :string

    field :status,
          Ch,
          type: "Enum8('pending' = 0, 'running' = 1, 'success' = 2, 'failure' = 3, 'skipped' = 4)"

    field :duration_ms, Ch, type: "Nullable(Int32)"
    field :started_at, Ch, type: "DateTime64(6)"
    field :finished_at, Ch, type: "Nullable(DateTime64(6))"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(job_step, attrs) do
    job_step
    |> cast(attrs, [
      :id,
      :job_run_id,
      :step_number,
      :step_name,
      :status,
      :duration_ms,
      :started_at,
      :finished_at,
      :inserted_at
    ])
    |> validate_required([
      :id,
      :job_run_id,
      :step_number,
      :step_name,
      :status,
      :started_at
    ])
  end
end
