defmodule Symptoms.Store.Change do
  @moduledoc """
  A change event from a source's `changes/2`. `category` is `code`, `config` or `migration`.
  """
  use Ecto.Schema

  schema "changes" do
    field :source, :string
    field :kind, :string
    field :category, :string
    field :ref, :string
    field :at, :utc_datetime_usec
    field :service, :string
    field :touched_entity_ids, {:array, :integer}, default: []
    field :before, :map
    field :after, :map
    field :inserted_at, :utc_datetime_usec
  end
end
