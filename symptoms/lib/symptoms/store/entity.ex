defmodule Symptoms.Store.Entity do
  @moduledoc """
  The catalogue: one row per `(environment, service, kind, key)`. `aliases` are other keys of the same kind that resolve here; `family` groups entities whose history a new entity borrows; `unknown` marks an entity whose source could not read its input (README "Presence"). The start of its current degraded run per pipeline is a `Symptoms.Store.DegradedRun`.
  """
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec]
  schema "entities" do
    field :environment, :string
    field :service, :string
    field :kind, :string
    field :key, :string
    field :family, :string
    field :aliases, {:array, :string}, default: []
    field :first_seen_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :last_evidence_at, :utc_datetime_usec
    field :retired_at, :utc_datetime_usec
    field :unknown, :boolean, default: false
    field :unknown_since, :utc_datetime_usec
    field :unknown_streams, {:array, :string}, default: []
    timestamps()
  end
end
