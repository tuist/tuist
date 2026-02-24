defmodule Cache.Repo.Migrations.CreateKeyValueEntryHashes do
  @moduledoc false
  use Ecto.Migration

  def up do
    create table(:key_value_entry_hashes) do
      add(:key_value_entry_id, references(:key_value_entries, on_delete: :delete_all), null: false)
      add(:account_handle, :text, null: false)
      add(:project_handle, :text, null: false)
      add(:cas_hash, :text, null: false)
    end

    create(unique_index(:key_value_entry_hashes, [:key_value_entry_id, :cas_hash]))
    create(index(:key_value_entry_hashes, [:account_handle, :project_handle, :cas_hash]))
    create(index(:key_value_entry_hashes, [:key_value_entry_id]))

    execute("""
    WITH parsed AS (
      SELECT
        id,
        json_payload,
        substr(key, 10) AS remainder
      FROM key_value_entries
      WHERE key LIKE 'keyvalue:%:%:%'
        AND json_valid(json_payload) = 1
    ),
    scoped AS (
      SELECT
        id,
        json_payload,
        substr(remainder, 1, instr(remainder, ':') - 1) AS account_handle,
        substr(
          substr(remainder, instr(remainder, ':') + 1),
          1,
          instr(substr(remainder, instr(remainder, ':') + 1), ':') - 1
        ) AS project_handle
      FROM parsed
      WHERE instr(remainder, ':') > 0
        AND instr(substr(remainder, instr(remainder, ':') + 1), ':') > 0
    )
    INSERT OR IGNORE INTO key_value_entry_hashes (key_value_entry_id, account_handle, project_handle, cas_hash)
    SELECT
      scoped.id,
      scoped.account_handle,
      scoped.project_handle,
      json_extract(entry.value, '$.value')
    FROM scoped
    JOIN json_each(scoped.json_payload, '$.entries') AS entry
    WHERE json_type(entry.value) = 'object'
      AND json_extract(entry.value, '$.value') IS NOT NULL
    """)
  end

  def down do
    drop(index(:key_value_entry_hashes, [:key_value_entry_id]))
    drop(index(:key_value_entry_hashes, [:account_handle, :project_handle, :cas_hash]))
    drop(unique_index(:key_value_entry_hashes, [:key_value_entry_id, :cas_hash]))
    drop(table(:key_value_entry_hashes))
  end
end
