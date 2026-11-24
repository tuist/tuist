defmodule Tuist.Pulse.SymptomAck do
  @moduledoc """
  A person acknowledged a symptom at a revision. `change_seq` orders it among
  the state changes the evaluator reads back. See `Tuist.Pulse.Symptoms`.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Pulse.Symptom

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "pulse_symptom_acks" do
    belongs_to :account, Account, type: :integer
    belongs_to :symptom, Symptom, type: Ecto.UUID
    belongs_to :user, User, type: :integer
    field :revision, :integer
    field :change_seq, :integer

    timestamps(type: :utc_datetime)
  end
end
