defmodule Tuist.Pulse.SymptomMute do
  @moduledoc """
  A mute of one phenomenon on one entity until `expires_at`, keyed by
  `scope_key` so muting the same scope again moves its expiry. `change_seq`
  orders it among the state changes the evaluator reads back. See
  `Tuist.Pulse.Symptoms`.
  """
  use Ecto.Schema

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Pulse.Symptom

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "pulse_symptom_mutes" do
    belongs_to :account, Account, type: :integer
    belongs_to :symptom, Symptom, type: Ecto.UUID
    belongs_to :user, User, type: :integer
    field :scope_key, :string
    field :environment, :string
    field :service, :string
    field :entity_kind, :string
    field :entity_key, :string
    field :phenomenon, :string
    field :expires_at, :utc_datetime
    field :change_seq, :integer

    timestamps(type: :utc_datetime)
  end
end
