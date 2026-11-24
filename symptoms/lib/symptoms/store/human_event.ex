defmodule Symptoms.Store.HumanEvent do
  @moduledoc """
  An investigation (`kind` is `investigation`) mirrored from the Tuist server's state.
  """
  use Ecto.Schema

  schema "human_events" do
    field :kind, :string
    field :symptom_id, Ecto.UUID
    field :data, :map
    field :change_seq, :integer
  end
end
