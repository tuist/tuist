defmodule Tuist.Pulse.Symptom do
  @moduledoc """
  The latest applied revision of a symptom mirrored from the symptoms
  evaluator. Typed columns hold what the Symptoms page filters and sorts on;
  nested parts of the revision stay as JSON. Titles, excerpts and evidence are
  masked by the evaluator but untrusted. See `Tuist.Pulse.Symptoms`.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "pulse_symptoms" do
    belongs_to :account, Account, type: :integer
    field :symptom_key, :string
    field :schema_version, :string
    field :revision, :integer
    field :seq, :integer
    field :state, Ecto.Enum, values: [:open, :resolved, :merged]
    field :tier, Ecto.Enum, values: [:audit, :board, :page]

    field :transition, Ecto.Enum, values: [:opened, :escalated, :deescalated, :merged, :resolved, :reopened, :annotated]

    field :merged_into, Ecto.UUID
    field :environment, :string
    field :service, :string
    field :entity_kind, :string
    field :entity_key, :string
    field :title, :string
    field :phenomenon_names, {:array, :string}, default: []
    field :phenomena, {:array, :map}, default: []
    field :score, :float
    field :p_degraded, :float
    field :impact_unit, :string
    field :impact_rate, :float
    field :budget_price, :float
    field :decision, :map
    field :root, :map
    field :suspected_change, :map
    field :evidence, :map
    field :brief_ref, :string
    field :outcome, :map
    field :opened_at, :utc_datetime
    field :revised_at, :utc_datetime
    field :resolved_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
