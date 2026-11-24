defmodule Tuist.Pulse.SymptomRevision do
  @moduledoc """
  A revision of a symptom the mirror applied, keyed by symptom and revision,
  with the evaluator's log `seq` and the full snapshot. See
  `Tuist.Pulse.Symptoms`.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Pulse.Symptom

  @primary_key false
  schema "pulse_symptom_revisions" do
    belongs_to :symptom, Symptom, type: Ecto.UUID, primary_key: true
    field :revision, :integer, primary_key: true
    belongs_to :account, Account, type: :integer
    field :seq, :integer
    field :state, Ecto.Enum, values: [:open, :resolved, :merged]
    field :tier, Ecto.Enum, values: [:audit, :board, :page]

    field :transition, Ecto.Enum, values: [:opened, :escalated, :deescalated, :merged, :resolved, :reopened, :annotated]

    field :revised_at, :utc_datetime
    field :document, :map

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
