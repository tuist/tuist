defmodule Symptoms.Store.Threshold do
  @moduledoc """
  The weekly CUSUM threshold `h` of one pipeline (`window_seconds`) chosen by `Symptoms.Evidence.Threshold.choose/3`, with its history; the latest row per pipeline is in force.
  """
  use Ecto.Schema

  schema "thresholds" do
    field :h, :float
    field :window_seconds, :integer, default: 60
    field :crossings, :integer
    field :entity_days, :float
    field :rate, :float
    field :inserted_at, :utc_datetime_usec
  end
end
