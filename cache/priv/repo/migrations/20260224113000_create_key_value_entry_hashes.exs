defmodule Cache.Repo.Migrations.CreateKeyValueEntryHashes do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:key_value_entry_hashes) do
      add(:key_value_entry_id, references(:key_value_entries, on_delete: :delete_all), null: false)
      add(:account_handle, :text, null: false)
      add(:project_handle, :text, null: false)
      add(:cas_hash, :text, null: false)
    end

    create(unique_index(:key_value_entry_hashes, [:key_value_entry_id, :cas_hash]))
    create(index(:key_value_entry_hashes, [:account_handle, :project_handle, :cas_hash]))
  end
end
