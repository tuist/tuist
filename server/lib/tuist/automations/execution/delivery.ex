defmodule Tuist.Automations.Execution.Delivery do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "automation_deliveries" do
    field :transition_id, Ecto.UUID
    field :position, :integer
    field :action, :map
    field :state, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end
