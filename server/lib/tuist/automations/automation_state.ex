defmodule Tuist.Automations.AutomationState do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "automation_states" do
    field :automation_id, Ecto.UUID
    field :test_case_id, Ecto.UUID
    field :status, Ch, type: "LowCardinality(String)"
    field :triggered_at, Ch, type: "DateTime64(6)"
    field :recovered_at, Ch, type: "Nullable(DateTime64(6))"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:id, :automation_id, :test_case_id, :status, :triggered_at, :recovered_at, :inserted_at])
    |> validate_required([:id, :automation_id, :test_case_id, :status, :triggered_at])
  end
end
