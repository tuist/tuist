defmodule Symptoms.Store.Reanchor do
  @moduledoc """
  A re-anchor decision for one deploy on one entity: `accepted`, `intended` (a shift above the caps, sent to the board) or `blocked`.
  """
  use Ecto.Schema

  schema "baseline_reanchors" do
    field :entity_id, :integer
    field :change_id, :integer
    field :from_version, :string
    field :to_version, :string
    field :status, :string
    field :error_ratio, :float
    field :p95_ratio, :float
    field :symptom_id, Ecto.UUID
    field :at, :utc_datetime_usec
  end
end
