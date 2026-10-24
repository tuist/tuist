defmodule Atlas.Automations.Event do
  use Atlas.Schema

  alias Atlas.Automations.Attempt
  alias Atlas.Automations.Run

  schema "automation_events" do
    belongs_to :run, Run
    belongs_to :attempt, Attempt
    field :sequence, :integer
    field :event, :string
    field :level, :string
    field :message, :string
    field :step_id, :string
    field :trace_id, :string
    field :span_id, :string
    field :metadata, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
