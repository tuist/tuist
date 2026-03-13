defmodule Cache.KeyValueEntriesTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueRepo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(KeyValueRepo)
    Application.put_env(:cache, :key_value_mode, :local)
    on_exit(fn -> Application.put_env(:cache, :key_value_mode, :local) end)
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
    Application.put_env(:cache, :key_value_mode, :distributed)

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
end
