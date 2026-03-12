defmodule Cache.KeyValueRepo.Migrations.DropKeyValueEntryHashes do
  use Ecto.Migration

  def change do
    drop_if_exists(index(:key_value_entry_hashes, [:account_handle, :project_handle, :cas_hash]))
    drop_if_exists(unique_index(:key_value_entry_hashes, [:key_value_entry_id, :cas_hash]))
    drop_if_exists(table(:key_value_entry_hashes))
  end
end
