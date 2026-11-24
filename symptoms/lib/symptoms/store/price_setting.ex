defmodule Symptoms.Store.PriceSetting do
  @moduledoc """
  The day and night interruption prices and the hard-floor impact rate, with their history; the latest row is in force.
  """
  use Ecto.Schema

  schema "price_settings" do
    field :day_price, :float
    field :night_price, :float
    field :floor_rate, :float
    field :reason, :string
    field :details, :map, default: %{}
    field :inserted_at, :utc_datetime_usec
  end
end
