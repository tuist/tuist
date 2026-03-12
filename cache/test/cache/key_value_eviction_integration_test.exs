defmodule Cache.KeyValueEvictionIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic
  use Oban.Testing, repo: Cache.Repo

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueEntryHash
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

    enqueued = all_enqueued(worker: XcodeCleanupWorker)
    assert length(enqueued) == 1

    assert [%{args: args}] = enqueued
    assert args["account_handle"] == "acme"
    assert args["project_handle"] == "ios"
    assert Enum.sort(args["cas_hashes"]) == 1..10 |> Enum.map(&"HASH_#{&1}") |> Enum.sort()
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
