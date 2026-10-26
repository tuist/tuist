defmodule Tuist.Automations.Execution.Evaluation do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "automation_evaluations" do
    field :alert_id, Ecto.UUID
    field :revision, :binary
    field :state, :string, default: "running"
    field :scope, :map, default: %{}
    field :cursor, :map
    field :evaluated_at, :utc_datetime_usec
    field :baseline, :boolean
    timestamps(type: :utc_datetime)
  end
end
