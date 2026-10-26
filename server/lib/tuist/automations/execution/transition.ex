defmodule Tuist.Automations.Execution.Transition do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "automation_transitions" do
    field :state_id, Ecto.UUID
    field :revision, :binary
    field :sequence, :integer
    field :status, :string
    field :phase, :string, default: "pending"
    field :actions, {:array, :map}, default: []
    field :event_types, {:array, :string}, default: []
    field :snapshot, :map
    field :occurred_at, :utc_datetime_usec
    field :error, :string
    field :depth, :integer, default: 0
    field :source_id, Ecto.UUID
    field :fanout_done, :boolean, default: false
    timestamps(type: :utc_datetime)
  end
end
