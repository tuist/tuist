defmodule Cache.Repo.Migrations.CreateKeyValueEntryHashes do
  @moduledoc false
  use Ecto.Migration

  require Logger

  @batch_size 50_000

  def up do
    create table(:key_value_entry_hashes) do
      add(:key_value_entry_id, references(:key_value_entries, on_delete: :delete_all), null: false)
      add(:account_handle, :text, null: false)
      add(:project_handle, :text, null: false)
      add(:cas_hash, :text, null: false)
    end

    # Unique index must exist before backfill (INSERT OR IGNORE depends on it)
    create(unique_index(:key_value_entry_hashes, [:key_value_entry_id, :cas_hash]))

    flush()

    backfill_hashes()

    # Non-unique indexes created after backfill for faster bulk insertion
    create(index(:key_value_entry_hashes, [:account_handle, :project_handle, :cas_hash]))
    create(index(:key_value_entry_hashes, [:key_value_entry_id]))
  end

  def down do
    drop(index(:key_value_entry_hashes, [:key_value_entry_id]))
    drop(index(:key_value_entry_hashes, [:account_handle, :project_handle, :cas_hash]))
    drop(unique_index(:key_value_entry_hashes, [:key_value_entry_id, :cas_hash]))
    drop(table(:key_value_entry_hashes))
  end

  defp backfill_hashes do
    %{rows: [[max_id]]} = repo().query!("SELECT COALESCE(MAX(id), 0) FROM key_value_entries")

    if max_id > 0 do
      Logger.info("Backfilling key_value_entry_hashes (max entry id: #{max_id})...")
      backfill_chunk(0, max_id, 0)
    end
  end

  defp backfill_chunk(from_id, max_id, total_inserted) when from_id >= max_id do
    Logger.info("Backfill complete: #{total_inserted} hash rows inserted")
  end

  defp backfill_chunk(from_id, max_id, total_inserted) do
    to_id = from_id + @batch_size

    %{num_rows: inserted} =
      repo().query!(
        """
        WITH batch AS (
          SELECT id, key, json_payload
          FROM key_value_entries
          WHERE id > ?1 AND id <= ?2
            AND key LIKE 'keyvalue:%:%:%'
            AND json_valid(json_payload) = 1
        ),
        parsed AS (
          SELECT
            id,
            json_payload,
            substr(key, 10) AS remainder
          FROM batch
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
        """,
        [from_id, to_id]
      )

    backfill_chunk(to_id, max_id, total_inserted + inserted)
  end
end
