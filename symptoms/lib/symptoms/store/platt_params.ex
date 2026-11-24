defmodule Symptoms.Store.PlattParams do
  @moduledoc """
  Platt parameters with their history, per pipeline (`window_seconds`); the latest row of a pipeline is in force. `kind` is `weekly` or `refit`.
  """
  use Ecto.Schema

  schema "platt_params" do
    field :a, :float
    field :b, :float
    field :kind, :string
    field :window_seconds, :integer, default: 60
    field :samples, :integer, default: 0
    field :details, :map, default: %{}
    field :inserted_at, :utc_datetime_usec
  end
end
