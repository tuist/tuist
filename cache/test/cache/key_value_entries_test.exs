defmodule Cache.KeyValueEntriesTest do
  use ExUnit.Case, async: false

  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  test "delete_expired returns list of expired entries with key and json_payload" do
    now = DateTime.utc_now()
    old_time = DateTime.add(now, -31, :day)

    entry =
      Repo.insert!(%KeyValueEntry{
        key: "old-entry",
        json_payload: ~s({"hash": "abc"}),
        last_accessed_at: old_time
      })

    {expired_entries, count} = KeyValueEntries.delete_expired(30)

    assert count == 1
    assert length(expired_entries) == 1

    returned_entry = hd(expired_entries)
    assert returned_entry.key == "old-entry"
    assert returned_entry.json_payload == ~s({"hash": "abc"})
    assert returned_entry.id == entry.id

    assert Repo.get(KeyValueEntry, entry.id) == nil
  end

  test "delete_expired does not return or delete fresh entries" do
    now = DateTime.utc_now()
    recent_time = DateTime.add(now, -10, :day)

    entry =
      Repo.insert!(%KeyValueEntry{
        key: "fresh-entry",
        json_payload: ~s({"hash": "def"}),
        last_accessed_at: recent_time
      })

    {expired_entries, count} = KeyValueEntries.delete_expired(30)

    assert count == 0
    assert expired_entries == []

    assert Repo.get(KeyValueEntry, entry.id)
  end

  test "delete_expired returns and deletes entries with nil last_accessed_at" do
    entry =
      Repo.insert!(%KeyValueEntry{
        key: "nil-accessed-entry",
        json_payload: ~s({"hash": "ghi"}),
        last_accessed_at: nil
      })

    {expired_entries, count} = KeyValueEntries.delete_expired(30)

    assert count == 1
    assert length(expired_entries) == 1

    returned_entry = hd(expired_entries)
    assert returned_entry.key == "nil-accessed-entry"

    assert returned_entry.json_payload == ~s({"hash": "ghi"}),
           "Should include json_payload field"

    assert returned_entry.id == entry.id

    assert Repo.get(KeyValueEntry, entry.id) == nil
  end

  test "delete_expired returns empty list when no entries are expired" do
    now = DateTime.utc_now()

    Repo.insert!(%KeyValueEntry{
      key: "recent-entry",
      json_payload: ~s({"hash": "jkl"}),
      last_accessed_at: now
    })

    {expired_entries, count} = KeyValueEntries.delete_expired(30)

    assert count == 0
    assert expired_entries == []
  end

  test "delete_expired respects max_age_days parameter" do
    now = DateTime.utc_now()
    eight_days_ago = DateTime.add(now, -8, :day)
    five_days_ago = DateTime.add(now, -5, :day)

    old_entry =
      Repo.insert!(%KeyValueEntry{
        key: "older-than-7-days",
        json_payload: ~s({"hash": "mno"}),
        last_accessed_at: eight_days_ago
      })

    fresh_entry =
      Repo.insert!(%KeyValueEntry{
        key: "within-7-days",
        json_payload: ~s({"hash": "pqr"}),
        last_accessed_at: five_days_ago
      })

    {expired_entries, count} = KeyValueEntries.delete_expired(7)

    assert count == 1
    assert length(expired_entries) == 1
    assert hd(expired_entries).key == "older-than-7-days"

    assert Repo.get(KeyValueEntry, old_entry.id) == nil
    assert Repo.get(KeyValueEntry, fresh_entry.id)
  end

  test "delete_expired respects 10,000 entry limit" do
    now = DateTime.utc_now()
    old_time = DateTime.add(now, -31, :day)

    for i <- 1..10_050 do
      Repo.insert!(%KeyValueEntry{
        key: "entry-#{i}",
        json_payload: ~s({"hash": "#{i}"}),
        last_accessed_at: old_time
      })
    end

    {expired_entries, count} = KeyValueEntries.delete_expired(30)

    assert count == 10_000
    assert length(expired_entries) == 10_000

    remaining = Repo.aggregate(KeyValueEntry, :count)
    assert remaining == 50
  end

  test "delete_expired returns entries with all required fields" do
    now = DateTime.utc_now()
    old_time = DateTime.add(now, -31, :day)

    Repo.insert!(%KeyValueEntry{
      key: "test-key",
      json_payload: ~s({"data": "value"}),
      last_accessed_at: old_time
    })

    {expired_entries, _count} = KeyValueEntries.delete_expired(30)

    returned_entry = hd(expired_entries)
    assert returned_entry.key
    assert returned_entry.json_payload
    assert returned_entry.id
  end

  test "referenced_hashes returns hashes still present in other KV entries" do
    Repo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:ROOT1",
      json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
      last_accessed_at: DateTime.utc_now()
    })

    Repo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:ROOT2",
      json_payload: ~s({"entries":[{"value":"EFGH5678"}]}),
      last_accessed_at: DateTime.utc_now()
    })

    result = KeyValueEntries.referenced_hashes("acme", "ios", ["ABCD1234", "EFGH5678", "MISSING"])

    assert Enum.sort(result) == ["ABCD1234", "EFGH5678"]
  end

  test "referenced_hashes returns empty list when no entries reference the hashes" do
    Repo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:ROOT1",
      json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
      last_accessed_at: DateTime.utc_now()
    })

    assert KeyValueEntries.referenced_hashes("acme", "ios", ["MISSING"]) == []
  end

  test "referenced_hashes scopes to account and project" do
    Repo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:ROOT1",
      json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
      last_accessed_at: DateTime.utc_now()
    })

    assert KeyValueEntries.referenced_hashes("other_account", "ios", ["ABCD1234"]) == []
    assert KeyValueEntries.referenced_hashes("acme", "android", ["ABCD1234"]) == []
  end

  test "referenced_hashes returns empty list for empty input" do
    assert KeyValueEntries.referenced_hashes("acme", "ios", []) == []
  end

  test "delete_expired handles mixed old and fresh entries correctly" do
    now = DateTime.utc_now()
    old_time = DateTime.add(now, -31, :day)
    recent_time = DateTime.add(now, -10, :day)

    old_entry_1 =
      Repo.insert!(%KeyValueEntry{
        key: "old-1",
        json_payload: ~s({"hash": "old1"}),
        last_accessed_at: old_time
      })

    fresh_entry =
      Repo.insert!(%KeyValueEntry{
        key: "fresh",
        json_payload: ~s({"hash": "fresh"}),
        last_accessed_at: recent_time
      })

    old_entry_2 =
      Repo.insert!(%KeyValueEntry{
        key: "old-2",
        json_payload: ~s({"hash": "old2"}),
        last_accessed_at: old_time
      })

    {expired_entries, count} = KeyValueEntries.delete_expired(30)

    assert count == 2
    assert length(expired_entries) == 2

    keys = expired_entries |> Enum.map(& &1.key) |> Enum.sort()
    assert keys == ["old-1", "old-2"]

    assert Repo.get(KeyValueEntry, old_entry_1.id) == nil
    assert Repo.get(KeyValueEntry, fresh_entry.id)
    assert Repo.get(KeyValueEntry, old_entry_2.id) == nil
  end
end
