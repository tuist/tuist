defmodule Symptoms.Store.Edge do
  @moduledoc """
  A caller → callee edge between entities, written by a source through `Symptoms.Store.put_edges/2`.
  """
  use Ecto.Schema

  schema "edges" do
    field :source, :string
    field :caller_id, :integer
    field :callee_id, :integer
    field :updated_at, :utc_datetime_usec
  end
end
