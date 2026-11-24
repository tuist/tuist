defmodule Symptoms.Store.Symptom do
  @moduledoc """
  A symptom's current state. `document` is the latest revision's snapshot (README "Symptom log"); `kind` is `detected` or `intended` (a deploy shift above the re-anchor caps).
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]
  schema "symptoms" do
    field :symptom_key, :string
    field :kind, :string, default: "detected"
    field :root_key, :string
    field :entity_id, :integer
    field :phenomenon, :string
    field :state, :string
    field :tier, :string
    field :max_tier, :string
    field :revision, :integer, default: 0
    field :score, :float, default: 0.0
    field :max_score, :float, default: 0.0
    field :p_degraded, :float
    field :expected_cost, :float
    field :impact_unit, :string
    field :impact_rate, :float
    field :merged_into, Ecto.UUID
    field :charged, :boolean, default: false
    field :paged_at, :utc_datetime_usec
    field :page_logged_at, :utc_datetime_usec
    field :delayed_until, :utc_datetime_usec
    field :delay_probability, :float
    field :document, :map
    field :opened_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :last_revision_at, :utc_datetime_usec
    timestamps()
  end
end
