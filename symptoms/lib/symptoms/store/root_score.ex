defmodule Symptoms.Store.RootScore do
  @moduledoc """
  The combined log-evidence `x` and CUSUM `score` of one root in one window, kept 35 days for the threshold, price and refit replays. Only windows with a positive CUSUM or a symptom are stored.
  """
  use Ecto.Schema

  schema "root_scores" do
    field :root_key, :string
    field :window_seconds, :integer
    field :window_start, :utc_datetime_usec
    field :x, :float
    field :score, :float
    field :impact, :float
    field :symptom_id, Ecto.UUID
  end
end
