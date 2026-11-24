defmodule Tuist.Pulse.SymptomOutcome do
  @moduledoc """
  The outcome a person confirmed for a symptom: `bad` (it was a real problem)
  or `fine`. `change_seq` orders it among the state changes the evaluator
  reads back. See `Tuist.Pulse.Symptoms`.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Pulse.Symptom

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "pulse_symptom_outcomes" do
    belongs_to :account, Account, type: :integer
    belongs_to :symptom, Symptom, type: Ecto.UUID
    belongs_to :user, User, type: :integer
    field :outcome, Ecto.Enum, values: [:bad, :fine]
    field :change_seq, :integer

    timestamps(type: :utc_datetime)
  end
end
