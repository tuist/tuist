defmodule Cache.KeyValueEntryHash do
  @moduledoc false

  use Ecto.Schema

  schema "key_value_entry_hashes" do
    belongs_to :key_value_entry, Cache.KeyValueEntry
    field :account_handle, :string
    field :project_handle, :string
    field :cas_hash, :string
  end
end
