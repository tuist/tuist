defmodule Cache.KeyValueEntriesTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Entry
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueRepo
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup do
    :ok = Sandbox.checkout(KeyValueRepo)
    stub(Config, :key_value_mode, fn -> :local end)
    stub(Config, :distributed_kv_enabled?, fn -> false end)
    :ok
  end

  test "delete_expired deletes expired entries" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "old-entry",
        json_payload: ~s({"hash": "abc"}),
        last_accessed_at: old_time
      })

    {grouped_hashes, count, status} = KeyValueEntries.delete_expired(30)

    assert grouped_hashes == %{}
    assert count == 1
    assert status == :complete
    assert KeyValueRepo.get(KeyValueEntry, entry.id) == nil
  end

  test "distributed eviction skips pending replication rows" do
    stub(Config, :key_value_mode, fn -> :distributed end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)

    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    pending_entry =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "pending-entry",
        json_payload: ~s({"hash": "pending"}),
        last_accessed_at: old_time,
        source_updated_at: old_time,
        replication_enqueued_at: DateTime.utc_now()
      })

    expired_entry =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "expired-entry",
        json_payload: ~s({"hash": "expired"}),
        last_accessed_at: old_time,
        source_updated_at: old_time
      })

    {_grouped_hashes, count, status} = KeyValueEntries.delete_expired(30)

    assert count == 1
    assert status == :complete
    assert KeyValueRepo.get(KeyValueEntry, expired_entry.id) == nil
    assert KeyValueRepo.get(KeyValueEntry, pending_entry.id)
  end

  test "materialize_remote_entry inserts new rows and updates watermark" do
    source_updated_at = DateTime.utc_now()

    assert :inserted =
             KeyValueEntries.materialize_remote_entry(%{
               key: "keyvalue:acme:ios:cas",
               json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
               last_accessed_at: source_updated_at,
               source_updated_at: source_updated_at,
               source_node: "node-a"
             })

    record = KeyValueRepo.get_by!(KeyValueEntry, key: "keyvalue:acme:ios:cas")
    assert record.source_updated_at == source_updated_at

    assert :ok = KeyValueEntries.put_distributed_watermark(source_updated_at, record.key)
    watermark = KeyValueEntries.distributed_watermark()
    assert watermark.updated_at_value == source_updated_at
    assert watermark.key_value == record.key
  end

  test "materialize_remote_entry preserves newer local pending payloads" do
    local_source_updated_at = DateTime.utc_now()
    remote_source_updated_at = DateTime.add(local_source_updated_at, -60, :second)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:cas",
      json_payload: Jason.encode!(%{entries: [%{"value" => "local"}]}),
      last_accessed_at: local_source_updated_at,
      source_updated_at: local_source_updated_at,
      replication_enqueued_at: local_source_updated_at
    })

    assert :access_updated =
             KeyValueEntries.materialize_remote_entry(%{
               key: "keyvalue:acme:ios:cas",
               json_payload: Jason.encode!(%{entries: [%{"value" => "remote"}]}),
               last_accessed_at: DateTime.utc_now(),
               source_updated_at: remote_source_updated_at,
               source_node: "node-b"
             })

    record = KeyValueRepo.get_by!(KeyValueEntry, key: "keyvalue:acme:ios:cas")
    assert Jason.decode!(record.json_payload)["entries"] == [%{"value" => "local"}]
    assert record.replication_enqueued_at == local_source_updated_at
  end

  test "apply_remote_batch inserts rows and returns side effect metadata" do
    source_updated_at = DateTime.utc_now()

    row =
      remote_row("keyvalue:acme:ios:inserted",
        json_payload: Jason.encode!(%{entries: [%{"value" => "inserted"}]}),
        last_accessed_at: source_updated_at,
        source_updated_at: source_updated_at,
        updated_at: source_updated_at
      )

    assert {:ok, result} = KeyValueEntries.apply_remote_batch([row])
    assert result.processed_count == 1
    assert result.inserted_count == 1
    assert result.payload_updated_count == 0
    assert result.access_updated_count == 0
    assert result.deleted_count == 0
    assert result.last_processed_row.key == row.key
    assert result.invalidate_keys == [row.key]
    assert result.mark_lineage_keys == [row.key]
    assert result.clear_lineage_keys == []

    record = KeyValueRepo.get_by!(KeyValueEntry, key: row.key)
    assert record.source_updated_at == source_updated_at
    assert Jason.decode!(record.json_payload)["entries"] == [%{"value" => "inserted"}]
  end

  test "apply_remote_batch preserves newer local pending payloads and merges access time" do
    local_source_updated_at = DateTime.utc_now()
    remote_source_updated_at = DateTime.add(local_source_updated_at, -60, :second)
    remote_last_accessed_at = DateTime.add(local_source_updated_at, 5, :second)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:cas",
      json_payload: Jason.encode!(%{entries: [%{"value" => "local"}]}),
      last_accessed_at: local_source_updated_at,
      source_updated_at: local_source_updated_at,
      replication_enqueued_at: local_source_updated_at
    })

    row =
      remote_row("keyvalue:acme:ios:cas",
        json_payload: Jason.encode!(%{entries: [%{"value" => "remote"}]}),
        last_accessed_at: remote_last_accessed_at,
        source_updated_at: remote_source_updated_at,
        updated_at: remote_last_accessed_at,
        source_node: "node-b"
      )

    assert {:ok, result} = KeyValueEntries.apply_remote_batch([row])
    assert result.inserted_count == 0
    assert result.payload_updated_count == 0
    assert result.access_updated_count == 1
    assert result.invalidate_keys == []
    assert result.mark_lineage_keys == [row.key]

    record = KeyValueRepo.get_by!(KeyValueEntry, key: row.key)
    assert Jason.decode!(record.json_payload)["entries"] == [%{"value" => "local"}]
    assert record.last_accessed_at == remote_last_accessed_at
    assert record.replication_enqueued_at == local_source_updated_at
  end

  test "apply_remote_batch deletes tombstones only for non-pending rows" do
    deleted_at = DateTime.utc_now()

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:stale",
      json_payload: Jason.encode!(%{entries: []}),
      last_accessed_at: deleted_at,
      source_updated_at: deleted_at
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:pending",
      json_payload: Jason.encode!(%{entries: []}),
      last_accessed_at: deleted_at,
      source_updated_at: deleted_at,
      replication_enqueued_at: deleted_at
    })

    rows = [
      remote_row("keyvalue:acme:ios:stale", deleted_at: deleted_at, updated_at: deleted_at),
      remote_row("keyvalue:acme:ios:pending", deleted_at: deleted_at, updated_at: deleted_at)
    ]

    assert {:ok, result} = KeyValueEntries.apply_remote_batch(rows)
    assert result.processed_count == 2
    assert result.inserted_count == 0
    assert result.payload_updated_count == 0
    assert result.access_updated_count == 0
    assert result.deleted_count == 1
    assert result.mark_lineage_keys == []
    assert Enum.sort(result.invalidate_keys) == ["keyvalue:acme:ios:pending", "keyvalue:acme:ios:stale"]
    assert Enum.sort(result.clear_lineage_keys) == ["keyvalue:acme:ios:pending", "keyvalue:acme:ios:stale"]

    assert KeyValueRepo.get_by(KeyValueEntry, key: "keyvalue:acme:ios:stale") == nil
    assert KeyValueRepo.get_by(KeyValueEntry, key: "keyvalue:acme:ios:pending")
  end

  test "apply_remote_batch commits mixed inserts, updates, and deletes" do
    original_time = DateTime.add(DateTime.utc_now(), -120, :second)
    updated_time = DateTime.add(original_time, 60, :second)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:update",
      json_payload: Jason.encode!(%{entries: [%{"value" => "old"}]}),
      last_accessed_at: original_time,
      source_updated_at: original_time
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:delete",
      json_payload: Jason.encode!(%{entries: []}),
      last_accessed_at: original_time,
      source_updated_at: original_time
    })

    rows = [
      remote_row("keyvalue:acme:ios:insert", updated_at: updated_time),
      remote_row("keyvalue:acme:ios:update",
        json_payload: Jason.encode!(%{entries: [%{"value" => "new"}]}),
        last_accessed_at: updated_time,
        source_updated_at: updated_time,
        updated_at: updated_time
      ),
      remote_row("keyvalue:acme:ios:delete", deleted_at: updated_time, updated_at: updated_time)
    ]

    assert {:ok, result} = KeyValueEntries.apply_remote_batch(rows)
    assert result.processed_count == 3
    assert result.inserted_count == 1
    assert result.payload_updated_count == 1
    assert result.access_updated_count == 0
    assert result.deleted_count == 1

    assert Enum.sort(result.invalidate_keys) == [
             "keyvalue:acme:ios:delete",
             "keyvalue:acme:ios:insert",
             "keyvalue:acme:ios:update"
           ]

    assert Enum.sort(result.mark_lineage_keys) == ["keyvalue:acme:ios:insert", "keyvalue:acme:ios:update"]
    assert result.clear_lineage_keys == ["keyvalue:acme:ios:delete"]

    inserted = KeyValueRepo.get_by!(KeyValueEntry, key: "keyvalue:acme:ios:insert")
    updated = KeyValueRepo.get_by!(KeyValueEntry, key: "keyvalue:acme:ios:update")

    assert Jason.decode!(inserted.json_payload)["entries"] == [%{"value" => "keyvalue:acme:ios:insert"}]
    assert Jason.decode!(updated.json_payload)["entries"] == [%{"value" => "new"}]
    assert updated.source_updated_at == updated_time
    assert KeyValueRepo.get_by(KeyValueEntry, key: "keyvalue:acme:ios:delete") == nil
  end

  test "apply_remote_batch returns busy errors without committing" do
    row = remote_row("keyvalue:acme:ios:busy")

    stub(KeyValueRepo, :transaction, fn _fun ->
      raise %Exqlite.Error{message: "Database busy"}
    end)

    assert {:error, :busy} = KeyValueEntries.apply_remote_batch([row])
    assert KeyValueRepo.get_by(KeyValueEntry, key: row.key) == nil
  end

  test "delete_project_entries_before does not match handles containing SQL wildcards" do
    old_time = DateTime.add(DateTime.utc_now(), -1, :day)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:a_b:ios:target",
      json_payload: "{}",
      last_accessed_at: old_time,
      source_updated_at: old_time
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:axb:ios:bystander",
      json_payload: "{}",
      last_accessed_at: old_time,
      source_updated_at: old_time
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:a%b:mac:target",
      json_payload: "{}",
      last_accessed_at: old_time,
      source_updated_at: old_time
    })

    {keys, count} = KeyValueEntries.delete_project_entries_before("a_b", "ios", old_time)

    assert count == 1
    assert keys == ["keyvalue:a_b:ios:target"]

    remaining_keys = KeyValueRepo.all(from(entry in KeyValueEntry, select: entry.key))
    assert Enum.sort(remaining_keys) == ["keyvalue:a%b:mac:target", "keyvalue:axb:ios:bystander"]
  end

  test "delete_project_entries_before only returns keys that were actually deleted" do
    old_time = DateTime.add(DateTime.utc_now(), -1, :day)
    new_time = DateTime.utc_now()

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:old",
      json_payload: "{}",
      last_accessed_at: old_time,
      source_updated_at: old_time
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:new",
      json_payload: "{}",
      last_accessed_at: new_time,
      source_updated_at: new_time
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:pending",
      json_payload: "{}",
      last_accessed_at: old_time,
      source_updated_at: old_time,
      replication_enqueued_at: old_time
    })

    {keys, count} = KeyValueEntries.delete_project_entries_before("acme", "ios", old_time)

    assert count == 1
    assert keys == ["keyvalue:acme:ios:old"]

    remaining_keys = KeyValueRepo.all(from(entry in KeyValueEntry, select: entry.key))
    assert Enum.sort(remaining_keys) == ["keyvalue:acme:ios:new", "keyvalue:acme:ios:pending"]
  end

  test "delete_project_entries_before respects exact lexicographic key bounds" do
    old_time = DateTime.add(DateTime.utc_now(), -1, :day)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:target",
      json_payload: "{}",
      last_accessed_at: old_time,
      source_updated_at: old_time
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios",
      json_payload: "{}",
      last_accessed_at: old_time,
      source_updated_at: old_time
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios;",
      json_payload: "{}",
      last_accessed_at: old_time,
      source_updated_at: old_time
    })

    {keys, count} = KeyValueEntries.delete_project_entries_before("acme", "ios", old_time)

    assert count == 1
    assert keys == ["keyvalue:acme:ios:target"]

    remaining_keys = KeyValueRepo.all(from(entry in KeyValueEntry, select: entry.key))
    assert Enum.sort(remaining_keys) == ["keyvalue:acme:ios", "keyvalue:acme:ios;"]
  end

  test "delete_project_entries_before handles large candidate sets" do
    old_time = DateTime.add(DateTime.utc_now(), -1, :day)
    timestamp = DateTime.truncate(old_time, :second)

    rows =
      for i <- 1..1000 do
        %{
          key: "keyvalue:acme:ios:artifact-#{i}",
          json_payload: "{}",
          last_accessed_at: old_time,
          source_updated_at: old_time,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end

    {1000, _} = KeyValueRepo.insert_all(KeyValueEntry, rows)

    {keys, count} = KeyValueEntries.delete_project_entries_before("acme", "ios", old_time)

    assert count == 1000
    assert length(keys) == 1000
    assert KeyValueRepo.all(from(entry in KeyValueEntry, select: entry.key)) == []
  end

  defp remote_row(key, attrs \\ []) do
    timestamp = Keyword.get(attrs, :updated_at, DateTime.utc_now())

    %Entry{
      key: key,
      account_handle: Keyword.get(attrs, :account_handle, "acme"),
      project_handle: Keyword.get(attrs, :project_handle, "ios"),
      cas_id: Keyword.get(attrs, :cas_id, List.last(String.split(key, ":"))),
      json_payload: Keyword.get(attrs, :json_payload, Jason.encode!(%{entries: [%{"value" => key}]})),
      source_node: Keyword.get(attrs, :source_node, "node-a"),
      source_updated_at: Keyword.get(attrs, :source_updated_at, timestamp),
      last_accessed_at: Keyword.get(attrs, :last_accessed_at, timestamp),
      updated_at: timestamp,
      deleted_at: Keyword.get(attrs, :deleted_at)
    }
  end
end
