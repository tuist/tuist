defmodule Symptoms.Store.HumanOutcome do
  @moduledoc """
  A confirmed outcome (`bad` or `fine`) mirrored from the Tuist server's state.
  """
  use Ecto.Schema

  @primary_key {:symptom_id, Ecto.UUID, autogenerate: false}
  schema "human_outcomes" do
    field :outcome, :string
    field :confirmed_at, :utc_datetime_usec
    field :change_seq, :integer
  end
end
