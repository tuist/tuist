defmodule Cache.KeyValueEntryHash do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "key_value_entry_hashes" do
    belongs_to :key_value_entry, Cache.KeyValueEntry
    field :account_handle, :string
    field :project_handle, :string
    field :cas_hash, :string
  end

  @doc false
  def changeset(entry_hash, attrs) do
    entry_hash
    |> cast(attrs, [:key_value_entry_id, :account_handle, :project_handle, :cas_hash])
    |> validate_required([:key_value_entry_id, :account_handle, :project_handle, :cas_hash])
    |> unique_constraint([:key_value_entry_id, :cas_hash])
  end
end
