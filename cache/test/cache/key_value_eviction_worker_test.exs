defmodule Cache.KeyValueEvictionWorkerTest do
  use ExUnit.Case, async: false
  use Mimic
  use Oban.Testing, repo: Cache.Repo

  import ExUnit.CaptureLog

  alias Cache.Config
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueEvictionWorker
  alias Cache.KeyValueRepo
  alias Cache.XcodeCleanupWorker
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup do
    :ok = Sandbox.checkout(Cache.Repo)
    :ok = Sandbox.checkout(KeyValueRepo)
    :ok
  end

  test "deletes entries older than 30 days and keeps fresh ones" do
    now = DateTime.utc_now()
    old_time = DateTime.add(now, -31, :day)
    recent_time = DateTime.add(now, -10, :day)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "old-entry",
      json_payload: ~s({"hash": "abc"}),
      last_accessed_at: old_time
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "fresh-entry",
      json_payload: ~s({"hash": "def"}),
      last_accessed_at: recent_time
    })

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    entries = KeyValueRepo.all(KeyValueEntry)
    assert length(entries) == 1
    assert hd(entries).key == "fresh-entry"
  end

  test "returns :ok when no entries are expired" do
    now = DateTime.utc_now()

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "recent-entry",
      json_payload: ~s({"hash": "ghi"}),
      last_accessed_at: now
    })

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    entries = KeyValueRepo.all(KeyValueEntry)
    assert length(entries) == 1
  end

  test "enqueues XcodeCleanupWorker for expired keyvalue entries" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT_HASH",
        json_payload: ~s({"entries":[{"value":"ABCD1234"},{"value":"EFGH5678"}]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [%{args: args}] = all_enqueued(worker: XcodeCleanupWorker)
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert args["cas_hashes"] == ["ABCD1234", "EFGH5678"]
  end

  test "does not enqueue cleanup for expired entry with non-keyvalue key" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "old-entry",
      json_payload: ~s({"hash": "abc"}),
      last_accessed_at: old_time
    })

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [] = all_enqueued(worker: XcodeCleanupWorker)
  end

  test "does not enqueue cleanup when no hash rows are present" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "keyvalue:acme:ios:ROOT_HASH",
      json_payload: ~s({"hash":"abc"}),
      last_accessed_at: old_time
    })

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [] = all_enqueued(worker: XcodeCleanupWorker)
  end

  test "does not enqueue cleanup for entries without extracted hashes" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT_HASH",
        json_payload: ~s({"entries":[]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [] = all_enqueued(worker: XcodeCleanupWorker)
  end

  test "groups CAS hashes by account and project into a single cleanup job" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry_1 =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: old_time
      })

    entry_2 =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT2",
        json_payload: ~s({"entries":[{"value":"EFGH5678"}]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry_1, entry_2])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [%{args: args}] = all_enqueued(worker: XcodeCleanupWorker)
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert Enum.sort(args["cas_hashes"]) == ["ABCD1234", "EFGH5678"]
  end

  test "enqueues separate cleanup jobs for different projects" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry_1 =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: old_time
      })

    entry_2 =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:android:ROOT2",
        json_payload: ~s({"entries":[{"value":"EFGH5678"}]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry_1, entry_2])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    enqueued = all_enqueued(worker: XcodeCleanupWorker)
    assert length(enqueued) == 2

    projects = enqueued |> Enum.map(fn %{args: args} -> args["project_handle"] end) |> Enum.sort()
    assert projects == ["android", "ios"]
  end

  test "deduplicates CAS hashes within the same account and project" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    entry_1 =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: old_time
      })

    entry_2 =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT2",
        json_payload: ~s({"entries":[{"value":"ABCD1234"}]}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry_1, entry_2])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert [%{args: args}] = all_enqueued(worker: XcodeCleanupWorker)
    assert args["cas_hashes"] == ["ABCD1234"]
  end

  test "chunks cleanup jobs when a project has many hashes" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    many_entries =
      for i <- 1..501 do
        %{"value" => "HASH#{i}"}
      end

    entry =
      KeyValueRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT1",
        json_payload: JSON.encode!(%{"entries" => many_entries}),
        last_accessed_at: old_time
      })

    :ok = KeyValueEntries.replace_entry_hashes([entry])

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    enqueued = all_enqueued(worker: XcodeCleanupWorker)
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

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "older-than-7-days",
      json_payload: ~s({"hash": "jkl"}),
      last_accessed_at: eight_days_ago
    })

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "within-7-days",
      json_payload: ~s({"hash": "mno"}),
      last_accessed_at: five_days_ago
    })

    {_entries, count, status} = KeyValueEntries.delete_expired(7)
    assert count == 1
    assert status == :complete

    entries = KeyValueRepo.all(KeyValueEntry)
    assert length(entries) == 1
    assert hd(entries).key == "within-7-days"
  end

  test "size-based eviction stops when below release watermark" do
    call_count = :counters.new(1, [:atomics])

    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") ->
          {:ok, %{rows: []}}

        query == "PRAGMA page_count" ->
          if :counters.get(call_count, 1) > 0 do
            {:ok, %{rows: [[5_000_000]]}}
          else
            {:ok, %{rows: [[8_000_000]]}}
          end

        query == "PRAGMA freelist_count" ->
          {:ok, %{rows: [[0]]}}

        query == "PRAGMA page_size" ->
          {:ok, %{rows: [[4096]]}}

        query == "PRAGMA wal_checkpoint(PASSIVE)" ->
          {:ok, %{rows: [[0, 0, 0]]}}

        query == "PRAGMA incremental_vacuum(10000)" ->
          {:ok, %{rows: []}}
      end
    end)

    expect(KeyValueEntries, :delete_one_expired_batch, fn 1, opts ->
      assert opts[:batch_size] == 1000
      :counters.add(call_count, 1, 1)
      {%{{"acme", "ios"} => ["SIZE_HASH"]}, 5, :complete}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :size, status: :complete}
    assert measurements.entries_deleted == 5
    assert measurements.duration_ms >= 0

    assert [%{args: args}] = all_enqueued(worker: XcodeCleanupWorker)
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert args["cas_hashes"] == ["SIZE_HASH"]
  end

  test "size-based eviction can complete after maintenance-only shrink" do
    maintenance_runs = :counters.new(1, [:atomics])

    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") ->
          {:ok, %{rows: []}}

        query == "PRAGMA page_count" ->
          if :counters.get(maintenance_runs, 1) > 0 do
            {:ok, %{rows: [[5_000_000]]}}
          else
            {:ok, %{rows: [[8_000_000]]}}
          end

        query == "PRAGMA freelist_count" ->
          {:ok, %{rows: [[0]]}}

        query == "PRAGMA page_size" ->
          {:ok, %{rows: [[4096]]}}

        query == "PRAGMA wal_checkpoint(PASSIVE)" ->
          {:ok, %{rows: [[0, 0, 0]]}}

        query == "PRAGMA incremental_vacuum(10000)" ->
          :counters.add(maintenance_runs, 1, 1)
          {:ok, %{rows: []}}
      end
    end)

    stub(KeyValueEntries, :delete_one_expired_batch, fn _min_retention_days, _opts ->
      flunk("expected maintenance to shrink before deleting any KV entries")
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :size, status: :complete}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
    assert [] = all_enqueued(worker: XcodeCleanupWorker)
  end

  test "size-based eviction reports floor_limited when no entries to delete" do
    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") -> {:ok, %{rows: []}}
        query == "PRAGMA page_count" -> {:ok, %{rows: [[8_000_000]]}}
        query == "PRAGMA freelist_count" -> {:ok, %{rows: [[0]]}}
        query == "PRAGMA page_size" -> {:ok, %{rows: [[4096]]}}
        query == "PRAGMA wal_checkpoint(PASSIVE)" -> {:ok, %{rows: [[0, 0, 0]]}}
        query == "PRAGMA incremental_vacuum(10000)" -> {:ok, %{rows: []}}
      end
    end)

    expect(KeyValueEntries, :delete_one_expired_batch, fn 1, _opts ->
      {%{}, 0, :complete}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :size, status: :floor_limited}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
  end

  test "size-based eviction reports busy when initial maintenance hits lock contention" do
    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") ->
          {:ok, %{rows: []}}

        query == "PRAGMA page_count" ->
          {:ok, %{rows: [[8_000_000]]}}

        query == "PRAGMA freelist_count" ->
          {:ok, %{rows: [[0]]}}

        query == "PRAGMA page_size" ->
          {:ok, %{rows: [[4096]]}}

        query == "PRAGMA wal_checkpoint(PASSIVE)" ->
          {:error, %Exqlite.Error{message: "database is locked"}}
      end
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :size, status: :busy}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
  end

  test "size-based eviction reports time_limit_reached when deadline expires during eviction" do
    stub(Config, :key_value_eviction_max_duration_ms, fn -> 500 end)

    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") ->
          {:ok, %{rows: []}}

        query == "PRAGMA page_count" ->
          {:ok, %{rows: [[8_000_000]]}}

        query == "PRAGMA freelist_count" ->
          {:ok, %{rows: [[0]]}}

        query == "PRAGMA page_size" ->
          {:ok, %{rows: [[4096]]}}

        query == "PRAGMA wal_checkpoint(PASSIVE)" ->
          {:ok, %{rows: [[0, 0, 0]]}}

        query == "PRAGMA incremental_vacuum(10000)" ->
          {:ok, %{rows: []}}
      end
    end)

    expect(KeyValueEntries, :delete_one_expired_batch, fn 1, _opts ->
      Process.sleep(750)
      {%{}, 0, :complete}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :size, status: :time_limit_reached}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 500
  end

  test "size-based eviction stops at worker deadline" do
    stub(Config, :key_value_eviction_max_duration_ms, fn -> 0 end)

    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") -> {:ok, %{rows: []}}
        query == "PRAGMA page_count" -> {:ok, %{rows: [[8_000_000]]}}
        query == "PRAGMA freelist_count" -> {:ok, %{rows: [[0]]}}
        query == "PRAGMA page_size" -> {:ok, %{rows: [[4096]]}}
        query == "PRAGMA wal_checkpoint(PASSIVE)" -> {:ok, %{rows: [[0, 0, 0]]}}
        query == "PRAGMA incremental_vacuum(10000)" -> {:ok, %{rows: []}}
      end
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :time, status: :time_limit_reached}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
  end

  test "initial size probe reports unknown trigger when SQLite is busy" do
    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") -> {:ok, %{rows: []}}
        query == "PRAGMA page_count" -> {:error, %Exqlite.Error{message: "database is locked"}}
      end
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :unknown, status: :busy}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
  end

  test "busy lock contention exits safely" do
    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") -> {:ok, %{rows: []}}
        query == "PRAGMA page_count" -> {:ok, %{rows: [[10]]}}
        query == "PRAGMA freelist_count" -> {:ok, %{rows: [[0]]}}
        query == "PRAGMA page_size" -> {:ok, %{rows: [[4096]]}}
      end
    end)

    expect(KeyValueEntries, :delete_expired, fn _retention_days, _opts ->
      {%{}, 0, :busy}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :time, status: :busy}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
  end

  test "time-based eviction preserves partial cleanup work on busy contention" do
    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") -> {:ok, %{rows: []}}
        query == "PRAGMA page_count" -> {:ok, %{rows: [[10]]}}
        query == "PRAGMA freelist_count" -> {:ok, %{rows: [[0]]}}
        query == "PRAGMA page_size" -> {:ok, %{rows: [[4096]]}}
      end
    end)

    expect(KeyValueEntries, :delete_expired, fn _retention_days, _opts ->
      {%{{"acme", "ios"} => ["HASH1", "HASH2"]}, 2, :busy}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :time, status: :busy}
    assert measurements.entries_deleted == 2

    assert [%{args: args}] = all_enqueued(worker: XcodeCleanupWorker)
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert args["cas_hashes"] == ["HASH1", "HASH2"]
  end

  test "size-based eviction preserves partial cleanup work on busy contention" do
    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") -> {:ok, %{rows: []}}
        query == "PRAGMA page_count" -> {:ok, %{rows: [[8_000_000]]}}
        query == "PRAGMA freelist_count" -> {:ok, %{rows: [[0]]}}
        query == "PRAGMA page_size" -> {:ok, %{rows: [[4096]]}}
        query == "PRAGMA wal_checkpoint(PASSIVE)" -> {:ok, %{rows: [[0, 0, 0]]}}
        query == "PRAGMA incremental_vacuum(10000)" -> {:ok, %{rows: []}}
      end
    end)

    expect(KeyValueEntries, :delete_one_expired_batch, fn 1, _opts ->
      {%{{"acme", "ios"} => ["SIZE_HASH"]}, 3, :busy}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :size, status: :busy}
    assert measurements.entries_deleted == 3

    assert [%{args: args}] = all_enqueued(worker: XcodeCleanupWorker)
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert args["cas_hashes"] == ["SIZE_HASH"]
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
      capture_log(fun)
      assert_receive {^ref, [:cache, :kv, :eviction, :complete], measurements, metadata}
      {measurements, metadata}
    after
      :telemetry.detach(handler_id)
    end
  end
end
