defmodule Cache.KeyValueEvictionWorkerTest do
  use ExUnit.Case, async: false
  use Mimic
  use Oban.Testing, repo: Cache.Repo

  import ExUnit.CaptureLog

  alias Cache.CASCleanupWorker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueEvictionWorker
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

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

  test "respects configurable max age via delete_expired/2" do
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

    {_entries, count, status} = KeyValueEntries.delete_expired(7)
    assert count == 1
    assert status == :complete

    entries = Repo.all(KeyValueEntry)
    assert length(entries) == 1
    assert hd(entries).key == "within-7-days"
  end

  test "size-based eviction triggers when size exceeds limit" do
    stub(Repo, :query, fn query ->
      case query do
        "PRAGMA page_count" -> {:ok, %{rows: [[8_000_000]]}}
        "PRAGMA freelist_count" -> {:ok, %{rows: [[0]]}}
        "PRAGMA page_size" -> {:ok, %{rows: [[4096]]}}
        "PRAGMA wal_checkpoint(PASSIVE)" -> {:ok, %{rows: [[0, 0, 0]]}}
        "PRAGMA incremental_vacuum(1000)" -> {:ok, %{rows: []}}
      end
    end)

    expect(KeyValueEntries, :delete_expired, fn 30, opts ->
      assert opts[:batch_size] == 1000
      assert opts[:max_duration_ms] == 300_000
      {%{{"acme", "ios"} => ["SIZE_HASH"]}, 1, :time_limit_reached}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :size, status: :time_limit_reached}
    assert measurements.entries_deleted == 1
    assert measurements.duration_ms >= 0

    assert [%{args: args}] = all_enqueued(worker: CASCleanupWorker)
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert args["cas_hashes"] == ["SIZE_HASH"]
  end

  test "size-based eviction respects 24-hour retention floor" do
    stub(Repo, :query, fn query ->
      case query do
        "PRAGMA page_count" -> {:ok, %{rows: [[8_000_000]]}}
        "PRAGMA freelist_count" -> {:ok, %{rows: [[0]]}}
        "PRAGMA page_size" -> {:ok, %{rows: [[4096]]}}
        "PRAGMA wal_checkpoint(PASSIVE)" -> {:ok, %{rows: [[0, 0, 0]]}}
        "PRAGMA incremental_vacuum(1000)" -> {:ok, %{rows: []}}
      end
    end)

    parent = self()

    expect(KeyValueEntries, :delete_expired, 30, fn retention_days, _opts ->
      send(parent, {:retention_days, retention_days})
      {%{}, 0, :complete}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert_receive {:retention_days, 30}
    assert_receive {:retention_days, 29}
    assert_receive {:retention_days, 1}
    refute_receive {:retention_days, 0}

    assert metadata == %{trigger: :size, status: :floor_limited}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
  end

  test "busy lock contention exits safely" do
    stub(Repo, :query, fn query ->
      case query do
        "PRAGMA page_count" -> {:ok, %{rows: [[10]]}}
        "PRAGMA freelist_count" -> {:ok, %{rows: [[0]]}}
        "PRAGMA page_size" -> {:ok, %{rows: [[4096]]}}
      end
    end)

    expect(KeyValueEntries, :delete_expired, fn _retention_days, _opts ->
      raise %Exqlite.Error{message: "database is locked"}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :time, status: :busy}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
  end

  defp capture_eviction_telemetry(fun) do
    parent = self()
    ref = make_ref()
    handler_id = "kv-eviction-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:cache, :kv, :eviction, :complete],
        fn event, measurements, metadata, _config ->
          send(parent, {ref, event, measurements, metadata})
        end,
        nil
      )

    try do
      fun.()
      assert_receive {^ref, [:cache, :kv, :eviction, :complete], measurements, metadata}
      {measurements, metadata}
    after
      :telemetry.detach(handler_id)
    end
  end
end
