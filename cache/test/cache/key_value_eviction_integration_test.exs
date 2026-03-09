defmodule Cache.KeyValueEvictionIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic
  use Oban.Testing, repo: Cache.Repo

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Cache.CASCleanupWorker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueEntryHash
  alias Cache.KeyValueEvictionWorker
  alias Cache.KeyValueRepo
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup do
    :ok = Sandbox.checkout(Cache.Repo)
    :ok = Sandbox.checkout(KeyValueRepo)
    :ok
  end

  test "full eviction cycle removes expired entries, keeps fresh entries, and cascades hash rows" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)
    fresh_time = DateTime.add(DateTime.utc_now(), -1, :day)

    expired_entries =
      for i <- 1..10 do
        insert_entry(
          "keyvalue:acme:ios:ROOT_#{i}",
          Jason.encode!(%{"entries" => [%{"value" => "HASH_#{i}"}]}),
          old_time
        )
      end

    :ok = KeyValueEntries.replace_entry_hashes(expired_entries)

    fresh_entries =
      for i <- 1..10 do
        insert_entry(
          "keyvalue:acme:ios:FRESH_#{i}",
          Jason.encode!(%{"entries" => [%{"value" => "FRESH_HASH_#{i}"}]}),
          fresh_time
        )
      end

    :ok = KeyValueEntries.replace_entry_hashes(fresh_entries)

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    remaining_keys = KeyValueRepo.all(from(e in KeyValueEntry, select: e.key))

    assert length(remaining_keys) == 10

    assert Enum.sort(remaining_keys) ==
             1..10 |> Enum.map(&"keyvalue:acme:ios:FRESH_#{&1}") |> Enum.sort()

    expired_ids = Enum.map(expired_entries, & &1.id)
    fresh_ids = Enum.map(fresh_entries, & &1.id)

    assert KeyValueRepo.aggregate(from(h in KeyValueEntryHash, where: h.key_value_entry_id in ^expired_ids), :count) ==
             0

    assert KeyValueRepo.aggregate(from(h in KeyValueEntryHash, where: h.key_value_entry_id in ^fresh_ids), :count) ==
             10

    enqueued = all_enqueued(worker: CASCleanupWorker)
    assert length(enqueued) == 1

    assert [%{args: args}] = enqueued
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert Enum.sort(args["cas_hashes"]) == 1..10 |> Enum.map(&"HASH_#{&1}") |> Enum.sort()
  end

  test "size-based eviction stops when db drops below release watermark" do
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

        query == "PRAGMA incremental_vacuum(1000)" ->
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
        capture_log(fn ->
          assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
        end)
      end)

    assert metadata == %{trigger: :size, status: :complete}
    assert measurements.entries_deleted == 5
    assert measurements.duration_ms >= 0

    assert [%{args: args}] = all_enqueued(worker: CASCleanupWorker)
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert args["cas_hashes"] == ["SIZE_HASH"]
  end

  test "size-based eviction reports floor_limited when no entries eligible" do
    stub(KeyValueRepo, :query, fn query ->
      cond do
        String.starts_with?(query, "PRAGMA busy_timeout =") -> {:ok, %{rows: []}}
        query == "PRAGMA page_count" -> {:ok, %{rows: [[8_000_000]]}}
        query == "PRAGMA freelist_count" -> {:ok, %{rows: [[0]]}}
        query == "PRAGMA page_size" -> {:ok, %{rows: [[4096]]}}
      end
    end)

    expect(KeyValueEntries, :delete_one_expired_batch, fn 1, _opts ->
      {%{}, 0, :complete}
    end)

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        capture_log(fn ->
          assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
        end)
      end)

    assert metadata == %{trigger: :size, status: :floor_limited}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
  end

  test "lock contention exits safely and emits busy telemetry" do
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
        capture_log(fn ->
          assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
        end)
      end)

    assert metadata == %{trigger: :time, status: :busy}
    assert measurements.entries_deleted == 0
    assert measurements.duration_ms >= 0
  end

  test "eviction telemetry reports deletion count and duration for time-based eviction" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)
    fresh_time = DateTime.add(DateTime.utc_now(), -1, :day)

    for i <- 1..3 do
      insert_entry(
        "keyvalue:acme:ios:TELEMETRY_OLD_#{i}",
        Jason.encode!(%{"entries" => [%{"value" => "TELEMETRY_HASH_#{i}"}]}),
        old_time
      )
    end

    for i <- 1..2 do
      insert_entry(
        "keyvalue:acme:ios:TELEMETRY_FRESH_#{i}",
        Jason.encode!(%{"entries" => [%{"value" => "TELEMETRY_FRESH_HASH_#{i}"}]}),
        fresh_time
      )
    end

    {measurements, metadata} =
      capture_eviction_telemetry(fn ->
        capture_log(fn ->
          assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
        end)
      end)

    assert metadata == %{trigger: :time, status: :complete}
    assert measurements.entries_deleted == 3
    assert measurements.duration_ms >= 0
    assert KeyValueRepo.aggregate(KeyValueEntry, :count) == 2
  end

  defp insert_entry(key, json_payload, last_accessed_at) do
    KeyValueRepo.insert!(%KeyValueEntry{
      key: key,
      json_payload: json_payload,
      last_accessed_at: last_accessed_at
    })
  end

  defp capture_eviction_telemetry(fun) do
    parent = self()
    ref = make_ref()
    handler_id = "kv-eviction-integration-test-#{System.unique_integer([:positive])}"

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
