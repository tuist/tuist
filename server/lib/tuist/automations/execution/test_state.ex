defmodule Tuist.Automations.Execution.TestState do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "automation_test_states" do
    field :alert_id, Ecto.UUID
    field :generation, :integer
    field :test_case_id, Ecto.UUID
    field :status, :string
    field :triggered_at, :utc_datetime_usec
    field :sequence, :integer, default: 0
    field :pending_transition_id, Ecto.UUID
    timestamps(type: :utc_datetime)
  end
end
