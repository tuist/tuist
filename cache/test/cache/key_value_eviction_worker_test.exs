defmodule Cache.KeyValueEvictionWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Cache.Repo

  import ExUnit.CaptureLog

  alias Cache.CASCleanupWorker
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

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

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

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    entries = Repo.all(KeyValueEntry)
    assert length(entries) == 1
  end

  test "enqueues CASCleanupWorker for expired keyvalue entries" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT_HASH",
        json_payload: ~s({"entries":[{"value":"ABCD1234"},{"value":"EFGH5678"}]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [%{args: args}] = all_enqueued(worker: CASCleanupWorker)
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert args["cas_hashes"] == ["ABCD1234", "EFGH5678"]
  end

  test "does not enqueue cleanup for expired entry with non-keyvalue key" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    Repo.insert!(%KeyValueEntry{
      key: "old-entry",
      json_payload: ~s({"hash": "abc"}),
      last_accessed_at: old_time
    })

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [] = all_enqueued(worker: CASCleanupWorker)
  end

  test "does not enqueue cleanup when no hash rows are present" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    Repo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:ROOT_HASH",
      json_payload: ~s({"hash":"abc"}),
      last_accessed_at: old_time
    })

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [] = all_enqueued(worker: CASCleanupWorker)
  end

  test "does not enqueue cleanup for entries without extracted hashes" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT_HASH",
        json_payload: ~s({"entries":[]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [] = all_enqueued(worker: CASCleanupWorker)
  end

  test "groups CAS hashes by account and project into a single cleanup job" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry_1 =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: old_time
      })

    entry_2 =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT2",
        json_payload: ~s({"entries":[{"value":"EFGH5678"}]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry_1, entry_2])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [%{args: args}] = all_enqueued(worker: CASCleanupWorker)
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert Enum.sort(args["cas_hashes"]) == ["ABCD1234", "EFGH5678"]
  end

  test "enqueues separate cleanup jobs for different projects" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry_1 =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: old_time
      })

    entry_2 =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:android:ROOT2",
        json_payload: ~s({"entries":[{"value":"EFGH5678"}]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry_1, entry_2])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    enqueued = all_enqueued(worker: CASCleanupWorker)
    assert length(enqueued) == 2

    projects = enqueued |> Enum.map(fn %{args: args} -> args["project_handle"] end) |> Enum.sort()
    assert projects == ["android", "ios"]
  end

  test "deduplicates CAS hashes within the same account and project" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry_1 =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: old_time
      })

    entry_2 =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT2",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry_1, entry_2])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [%{args: args}] = all_enqueued(worker: CASCleanupWorker)
    assert args["cas_hashes"] == ["ABCD1234"]
  end

  test "chunks cleanup jobs when a project has many hashes" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    many_entries =
      for i <- 1..501 do
        %{"value" => "HASH#{i}"}
      end

    entry =
      Repo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: Jason.encode!(%{"entries" => many_entries}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    enqueued = all_enqueued(worker: CASCleanupWorker)
    assert length(enqueued) == 2

    hash_counts =
      enqueued
      |> Enum.map(fn %{args: args} -> length(args["cas_hashes"]) end)
      |> Enum.sort()

    assert hash_counts == [1, 500]
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

    {_entries, count} = KeyValueEntries.delete_expired(7)
    assert count == 1

    entries = Repo.all(KeyValueEntry)
    assert length(entries) == 1
    assert hd(entries).key == "within-7-days"
  end
end
