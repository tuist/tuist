defmodule Tuist.Pulse.SymptomStateEvent do
  @moduledoc """
  One ack, mute or outcome change with the user who made it, written in the
  same transaction as the state row it changed and never updated or deleted
  (a database trigger refuses both, except when the account is deleted). The
  state rows keep only the latest change; this is the trail. `details` holds
  what changed: the acked `revision`; a mute's `phenomenon`, entity,
  `expires_at` and `previous_expires_at`; an outcome's `outcome` and
  `previous`. See `Tuist.Pulse.Symptoms.history/2`.
  """
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "pulse_symptom_state_events" do
    field :account_id, :integer
    field :symptom_id, Ecto.UUID
    field :kind, Ecto.Enum, values: [:ack, :mute, :outcome]
    field :user_id, :integer
    field :change_seq, :integer
    field :details, :map, default: %{}
    field :inserted_at, :utc_datetime
  end
end
