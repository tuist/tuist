defmodule Cache.KeyValueEntriesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueEntryHash
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  test "delete_expired deletes expired entries and returns grouped hashes" do
    now = DateTime.utc_now()
    old_time = DateTime.add(now, -31, :day)

    entry =
      Repo.insert!(%KeyValueEntry{
        key: "old-entry",
        json_payload: ~s({"hash": "abc"}),
        last_accessed_at: old_time
      })

    {grouped_hashes, count} = KeyValueEntries.delete_expired(30)

    assert count == 1
    assert grouped_hashes == %{}

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

    {grouped_hashes, count} = KeyValueEntries.delete_expired(30)

    assert count == 0
    assert grouped_hashes == %{}

    assert Repo.get(KeyValueEntry, entry.id)
  end

  test "delete_expired deletes entries with nil last_accessed_at" do
    entry =
      Repo.insert!(%KeyValueEntry{
        key: "nil-accessed-entry",
        json_payload: ~s({"hash": "ghi"}),
        last_accessed_at: nil
      })

    {grouped_hashes, count} = KeyValueEntries.delete_expired(30)

    assert count == 1
    assert grouped_hashes == %{}

    assert Repo.get(KeyValueEntry, entry.id) == nil
  end

  test "delete_expired returns empty list when no entries are expired" do
    now = DateTime.utc_now()

    Repo.insert!(%KeyValueEntry{
      key: "recent-entry",
      json_payload: ~s({"hash": "jkl"}),
      last_accessed_at: now
    })

    {grouped_hashes, count} = KeyValueEntries.delete_expired(30)

    assert count == 0
    assert grouped_hashes == %{}
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

    {grouped_hashes, count} = KeyValueEntries.delete_expired(7)

    assert count == 1
    assert grouped_hashes == %{}

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

    {grouped_hashes, count} = KeyValueEntries.delete_expired(30)

    assert count == 10_000
    assert grouped_hashes == %{}

    remaining = Repo.aggregate(KeyValueEntry, :count)
    assert remaining == 50
  end

  test "delete_expired returns grouped hashes for keyvalue scoped entries" do
    now = DateTime.utc_now()
    old_time = DateTime.add(now, -31, :day)

    entry =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT_HASH",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    {grouped_hashes, count} = KeyValueEntries.delete_expired(30)

    assert count == 1
    assert grouped_hashes == %{{"acme", "ios"} => ["ABCD1234"]}
  end

  test "unreferenced_hashes excludes hashes still present in other KV entries" do
    entry_1 =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: DateTime.utc_now()
      })

    entry_2 =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT2",
        json_payload: ~s({"entries":[{"value":"EFGH5678"}]}),
        last_accessed_at: DateTime.utc_now()
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry_1, entry_2])

    result = KeyValueEntries.unreferenced_hashes(["ABCD1234", "EFGH5678", "MISSING"], "acme", "ios")

    assert result == ["MISSING"]
  end

  test "unreferenced_hashes returns all hashes when no entries reference them" do
    entry =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: DateTime.utc_now()
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    assert KeyValueEntries.unreferenced_hashes(["MISSING"], "acme", "ios") == ["MISSING"]
  end

  test "unreferenced_hashes scopes to account and project" do
    entry =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: DateTime.utc_now()
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    assert KeyValueEntries.unreferenced_hashes(["ABCD1234"], "other_account", "ios") == ["ABCD1234"]
    assert KeyValueEntries.unreferenced_hashes(["ABCD1234"], "acme", "android") == ["ABCD1234"]
  end

  test "unreferenced_hashes checks all entries in the payload, not just the first" do
    entry =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"FIRST"},{"value":"SECOND"},{"value":"THIRD"}]}),
        last_accessed_at: DateTime.utc_now()
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    assert KeyValueEntries.unreferenced_hashes(["SECOND"], "acme", "ios") == []
    assert KeyValueEntries.unreferenced_hashes(["THIRD"], "acme", "ios") == []
    assert KeyValueEntries.unreferenced_hashes(["FIRST", "THIRD", "MISSING"], "acme", "ios") == ["MISSING"]
  end

  test "unreferenced_hashes returns empty list for empty input" do
    assert KeyValueEntries.unreferenced_hashes([], "acme", "ios") == []
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

    {grouped_hashes, count} = KeyValueEntries.delete_expired(30)

    assert count == 2
    assert grouped_hashes == %{}

    assert Repo.get(KeyValueEntry, old_entry_1.id) == nil
    assert Repo.get(KeyValueEntry, fresh_entry.id)
    assert Repo.get(KeyValueEntry, old_entry_2.id) == nil
  end

  test "delete_expired removes hash references for deleted entries" do
    now = DateTime.utc_now()
    old_time = DateTime.add(now, -31, :day)

    old_entry =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:OLD",
        json_payload: ~s({"entries":[{"value":"OLD_HASH"}]}),
        last_accessed_at: old_time
      })

    fresh_entry =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:FRESH",
        json_payload: ~s({"entries":[{"value":"FRESH_HASH"}]}),
        last_accessed_at: now
      })

    :ok = KeyValueEntries.replace_entry_hashes([old_entry, fresh_entry])

    {_expired_entries, count} = KeyValueEntries.delete_expired(30)
    assert count == 1

    old_refs = Repo.all(from(h in KeyValueEntryHash, where: h.key_value_entry_id == ^old_entry.id))
    fresh_refs = Repo.all(from(h in KeyValueEntryHash, where: h.key_value_entry_id == ^fresh_entry.id))

    assert old_refs == []
    assert length(fresh_refs) == 1
    assert hd(fresh_refs).cas_hash == "FRESH_HASH"
  end
end
