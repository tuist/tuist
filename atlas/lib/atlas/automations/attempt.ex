defmodule Atlas.Automations.Attempt do
  use Atlas.Schema

  alias Atlas.Automations.Run

  schema "automation_attempts" do
    belongs_to :run, Run
    field :step_id, :string
    field :status, :string
    field :executor, :string, default: "local"
    field :input, :map
    field :output, :map
    field :error, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :execution_duration_ms, :integer
    field :wait_started_at, :utc_datetime_usec
    field :wait_duration_ms, :integer
    field :trace_id, :string
    field :span_id, :string
    field :parent_span_id, :string
    field :job_id, :integer
    field :job_attempt, :integer
    field :diagnostic, :map
    timestamps(type: :utc_datetime)
  end
end
