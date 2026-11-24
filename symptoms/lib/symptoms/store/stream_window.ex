defmodule Symptoms.Store.StreamWindow do
  @moduledoc """
  One evidence record per `(entity, source, window)`: the raw statistic, its conformal p-value and capped e-value, whether a symptom on the entity was open, and the symptom whose degraded run it belongs to (`symptom_id`). Kept 35 days; the stream's null history for `Symptoms.Evidence.Calibration`.
  """
  use Ecto.Schema

  schema "stream_windows" do
    field :entity_id, :integer
    field :source, :string
    field :phenomenon, :string
    field :window_seconds, :integer
    field :window_start, :utc_datetime_usec
    field :statistic, :float
    field :p, :float
    field :e, :float
    field :observed, :float
    field :expected, :float
    field :n, :integer
    field :impact_unit, :string
    field :impact_rate, :float
    field :examples, {:array, :string}, default: []
    field :open_symptom, :boolean, default: false
    field :symptom_id, Ecto.UUID
    field :inserted_at, :utc_datetime_usec
  end
end
