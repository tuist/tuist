defmodule Symptoms.Store.HumanAck do
  @moduledoc """
  An ack mirrored from the Tuist server's state.
  """
  use Ecto.Schema

  @primary_key {:symptom_id, Ecto.UUID, autogenerate: false}
  schema "human_acks" do
    field :revision, :integer
    field :acked_at, :utc_datetime_usec
    field :change_seq, :integer
  end
end
