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
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup do
    :ok = Sandbox.checkout(Cache.Repo)
    :ok = Sandbox.checkout(KeyValueRepo)
    stub(Config, :key_value_mode, fn -> :local end)
    stub(Config, :distributed_kv_enabled?, fn -> false end)
    :ok
  end

  test "deletes entries older than 30 days and keeps fresh ones" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)
    recent_time = DateTime.add(DateTime.utc_now(), -10, :day)

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
    assert Enum.map(entries, & &1.key) == ["fresh-entry"]
    assert [] = all_enqueued()
  end

  test "distributed eviction skips rows pending replication" do
    stub(Config, :key_value_mode, fn -> :distributed end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)

    old_time = DateTime.add(DateTime.utc_now(), -31, :day)

    KeyValueRepo.insert!(%KeyValueEntry{
      key: "pending-entry",
      json_payload: ~s({"hash": "abc"}),
      last_accessed_at: old_time,
      source_updated_at: old_time,
      replication_enqueued_at: DateTime.utc_now()
    })

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    assert KeyValueRepo.get_by!(KeyValueEntry, key: "pending-entry")
  end

  test "size-based eviction emits telemetry" do
    call_count = :counters.new(1, [:atomics])

    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") ->
          {:ok, %{rows: []}}

        query == "PRAGMA page_count" ->
          if(:counters.get(call_count, 1) > 0, do: {:ok, %{rows: [[5_000_000]]}}, else: {:ok, %{rows: [[8_000_000]]}})

        query == "PRAGMA freelist_count" ->
          {:ok, %{rows: [[0]]}}

        query == "PRAGMA page_size" ->
          {:ok, %{rows: [[4096]]}}

        query == "PRAGMA wal_checkpoint(PASSIVE)" ->
          {:ok, %{rows: [[0, 0, 0]]}}

        query == "PRAGMA incremental_vacuum(1000)" ->
          {:ok, %{rows: []}}
      end
    end)

    expect(KeyValueEntries, :delete_one_expired_batch, fn 1, opts ->
      assert opts[:batch_size] == 1000
      :counters.add(call_count, 1, 1)
      {%{}, 5, :complete}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
      end)

    assert metadata == %{trigger: :size, status: :complete}
    assert measurements.entries_deleted == 5
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
