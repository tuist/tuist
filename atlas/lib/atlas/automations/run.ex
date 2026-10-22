defmodule Atlas.Automations.Run do
  use Atlas.Schema

  alias Atlas.Automations.Attempt
  alias Atlas.Automations.Revision
  alias Atlas.Users.User

  schema "automation_runs" do
    belongs_to :revision, Revision
    belongs_to :initiated_by, User
    field :status, :string, default: "queued"
    field :trigger, :string, default: "manual"
    field :admission_key, :string
    field :input, :map, default: %{}
    field :outputs, :map, default: %{}
    field :cursor, :integer, default: 0
    field :last_error, :string
    field :completed_at, :utc_datetime
    field :trace_id, :string
    field :trace_flags, :integer, default: 1
    field :span_id, :string
    field :trace_started_at, :utc_datetime_usec
    field :trace_completed_at, :utc_datetime_usec
    field :event_sequence, :integer, default: 0
    has_many :attempts, Attempt
    timestamps(type: :utc_datetime)
  end
end
