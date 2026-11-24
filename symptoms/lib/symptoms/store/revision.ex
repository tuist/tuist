defmodule Symptoms.Store.Revision do
  @moduledoc """
  One entry of the append-only symptom log: a full snapshot of at most 16 KB with its global `seq`. Kept 30 days.
  """
  use Ecto.Schema

  @primary_key {:seq, :integer, autogenerate: false}
  schema "symptom_revisions" do
    field :symptom_id, Ecto.UUID
    field :revision, :integer
    field :document, :map
    field :inserted_at, :utc_datetime_usec
  end
end
