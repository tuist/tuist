defmodule Symptoms.Store.HumanMute do
  @moduledoc """
  A mute of one phenomenon on one entity until `expires_at`, mirrored from the Tuist server's state.
  """
  use Ecto.Schema

  schema "human_mutes" do
    field :environment, :string
    field :service, :string
    field :kind, :string
    field :key, :string
    field :phenomenon, :string
    field :expires_at, :utc_datetime_usec
    field :symptom_id, Ecto.UUID
    field :change_seq, :integer
  end
end
