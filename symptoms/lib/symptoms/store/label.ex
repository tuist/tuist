defmodule Symptoms.Store.Label do
  @moduledoc """
  A training label derived from a confirmed outcome (README "Labels"). `independent` is false for system-caused outcomes, which are recorded but never trained on; `weight` is the inverse of the recorded delay probability.
  """
  use Ecto.Schema

  @primary_key {:symptom_id, Ecto.UUID, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  schema "labels" do
    field :outcome, :string
    field :independent, :boolean
    field :cause, :string
    field :weight, :float
    field :score, :float
    field :max_tier, :string
    field :missed, :boolean
    field :delay_probability, :float
    field :delayed, :boolean, default: false
    field :phenomena, {:array, :map}, default: []
    field :confirmed_at, :utc_datetime_usec
    timestamps()
  end
end
