defmodule Atlas.Signals.Signal do
  @moduledoc false
  use Atlas.Schema

  alias Atlas.Automations.Run
  alias Atlas.Encrypted.Binary
  alias Atlas.Orbit.Thread
  alias Atlas.Signals.Source

  schema "signals" do
    belongs_to :source, Source
    belongs_to :thread, Thread
    belongs_to :execution, Run
    field :external_id, :string
    field :correlation_key, :string
    field :type, :string
    field :schema_version, :integer
    field :occurred_at, :utc_datetime_usec
    field :observed_at, :utc_datetime_usec
    field :envelope, Binary, redact: true
    field :status, :string, default: "pending"
    field :priority, :string
    field :decision, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
