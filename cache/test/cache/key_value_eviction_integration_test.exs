defmodule Cache.KeyValueEvictionIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic
  use Oban.Testing, repo: Cache.Repo

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Cache.Config
  alias Cache.KeyValueEntry
  alias Cache.KeyValueEvictionWorker
  alias Cache.KeyValueRepo
  alias Cache.KeyValueWriteRepo
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup do
    :ok = Sandbox.checkout(Cache.Repo)
    :ok = Cache.KeyValueRepoTestHelpers.reset!()
    stub(Config, :key_value_mode, fn -> :local end)
    stub(Config, :distributed_kv_enabled?, fn -> false end)
    :ok
  end

  test "full eviction cycle removes expired entries and keeps fresh entries" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)
    fresh_time = DateTime.add(DateTime.utc_now(), -1, :day)

    for index <- 1..10 do
      KeyValueWriteRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:ROOT_#{index}",
        json_payload: JSON.encode!(%{"entries" => [%{"value" => "HASH_#{index}"}]}),
        last_accessed_at: old_time
      })
    end

    for index <- 1..10 do
      KeyValueWriteRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:FRESH_#{index}",
        json_payload: JSON.encode!(%{"entries" => [%{"value" => "FRESH_HASH_#{index}"}]}),
        last_accessed_at: fresh_time
      })
    end

    capture_log(fn ->
      assert :ok = KeyValueEvictionWorker.perform(%Oban.Job{args: %{}})
    end)

    remaining_keys = KeyValueRepo.all(from(entry in KeyValueEntry, select: entry.key))
    assert length(remaining_keys) == 10
    assert Enum.all?(remaining_keys, &String.contains?(&1, "FRESH_"))
    assert [] = all_enqueued()
  end

  test "eviction telemetry reports deletion count and duration for time-based eviction" do
    old_time = DateTime.add(DateTime.utc_now(), -31, :day)
    fresh_time = DateTime.add(DateTime.utc_now(), -1, :day)

    for index <- 1..3 do
      KeyValueWriteRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:TELEMETRY_OLD_#{index}",
        json_payload: JSON.encode!(%{"entries" => [%{"value" => "TELEMETRY_HASH_#{index}"}]}),
        last_accessed_at: old_time
      })
    end

    for index <- 1..2 do
      KeyValueWriteRepo.insert!(%KeyValueEntry{
        key: "keyvalue:acme:ios:TELEMETRY_FRESH_#{index}",
        json_payload: JSON.encode!(%{"entries" => [%{"value" => "TELEMETRY_FRESH_HASH_#{index}"}]}),
        last_accessed_at: fresh_time
      })
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
