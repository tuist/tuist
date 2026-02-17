defmodule Cache.KeyValueEvictionWorkerTest do
  use ExUnit.Case, async: false

  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueEvictionWorker
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok
  end

  test "deletes entries older than 30 days and keeps fresh ones" do
    now = DateTime.utc_now()
    old_time = DateTime.add(now, -31, :day)
    recent_time = DateTime.add(now, -10, :day)

    Repo.insert!(%KeyValueEntry{
      key: "old-entry",
      json_payload: ~s({"hash": "abc"}),
      last_accessed_at: old_time
    })

    Repo.insert!(%KeyValueEntry{
      key: "fresh-entry",
      json_payload: ~s({"hash": "def"}),
      last_accessed_at: recent_time
    })

    assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})

    entries = Repo.all(KeyValueEntry)
    assert length(entries) == 1
    assert hd(entries).key == "fresh-entry"
  end

  test "returns :ok when no entries are expired" do
    now = DateTime.utc_now()

    Repo.insert!(%KeyValueEntry{
      key: "recent-entry",
      json_payload: ~s({"hash": "ghi"}),
      last_accessed_at: now
    })

    assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})

    entries = Repo.all(KeyValueEntry)
    assert length(entries) == 1
  end

  test "respects configurable max age via delete_expired/1" do
    now = DateTime.utc_now()
    eight_days_ago = DateTime.add(now, -8, :day)
    five_days_ago = DateTime.add(now, -5, :day)

    Repo.insert!(%KeyValueEntry{
      key: "older-than-7-days",
      json_payload: ~s({"hash": "jkl"}),
      last_accessed_at: eight_days_ago
    })

    Repo.insert!(%KeyValueEntry{
      key: "within-7-days",
      json_payload: ~s({"hash": "mno"}),
      last_accessed_at: five_days_ago
    })

    {count, _} = KeyValueEntries.delete_expired(7)
    assert count == 1

    entries = Repo.all(KeyValueEntry)
    assert length(entries) == 1
    assert hd(entries).key == "within-7-days"
  end
end
