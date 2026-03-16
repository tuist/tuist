defmodule Cache.KeyValueReplicationPollerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Repo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueReplicationPoller

  setup :set_mimic_from_context

  setup do
    Application.put_env(:cache, :key_value_mode, :distributed)
    Application.put_env(:cache, :distributed_kv_node_name, "test-node")
    on_exit(fn -> Application.put_env(:cache, :key_value_mode, :local) end)
    :ok
  end

  test "poll_now drains multiple full pages before returning" do
    parent = self()
    {:ok, watermark_agent} = Agent.start_link(fn -> %{updated_at_value: ~U[1970-01-01 00:00:00Z], key_value: ""} end)
    {:ok, calls_agent} = Agent.start_link(fn -> 0 end)
    {:ok, materialized_agent} = Agent.start_link(fn -> 0 end)
    {:ok, watermark_puts_agent} = Agent.start_link(fn -> 0 end)

    base_time = DateTime.add(DateTime.utc_now(), -120, :second)
    page_size = 1000

    make_row = fn i ->
      updated_at = DateTime.add(base_time, i, :second)

      %Entry{
        key: "keyvalue:acme:ios:cas-#{i}",
        account_handle: "acme",
        project_handle: "ios",
        cas_id: "cas-#{i}",
        json_payload: Jason.encode!(%{entries: []}),
        source_node: "node-a",
        source_updated_at: updated_at,
        last_accessed_at: updated_at,
        updated_at: updated_at,
        deleted_at: nil
      }
    end

    page_1 = Enum.map(1..page_size, make_row)
    page_2 = Enum.map((page_size + 1)..(2 * page_size), make_row)
    page_3 = Enum.map((2 * page_size + 1)..(2 * page_size + 200), make_row)

    stub(KeyValueEntries, :distributed_watermark, fn -> Agent.get(watermark_agent, & &1) end)

    stub(KeyValueEntries, :estimated_size_bytes, fn ->
      send(parent, :poll_complete)
      0
    end)

    stub(KeyValueEntries, :materialize_remote_entry, fn _attrs ->
      Agent.update(materialized_agent, &(&1 + 1))
      :payload_updated
    end)

    stub(KeyValueEntries, :put_distributed_watermark, fn updated_at, key ->
      Agent.update(watermark_agent, fn _ -> %{updated_at_value: updated_at, key_value: key} end)
      Agent.update(watermark_puts_agent, &(&1 + 1))
      :ok
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)

    stub(Repo, :all, fn _query, _opts ->
      Agent.get_and_update(calls_agent, fn count ->
        next_count = count + 1

        result =
          case next_count do
            1 -> page_1
            2 -> page_2
            3 -> page_3
            _ -> []
          end

        {result, next_count}
      end)
    end)

    start_supervised!(KeyValueReplicationPoller)
    assert_receive :poll_complete, 10_000

    total_materialized = Agent.get(materialized_agent, & &1)
    total_watermark_puts = Agent.get(watermark_puts_agent, & &1)
    total_calls = Agent.get(calls_agent, & &1)

    assert total_materialized == 2200
    assert total_watermark_puts == 3
    assert total_calls == 3
  end

  test "poller materializes alive rows and advances watermark" do
    parent = self()
    {:ok, watermark_agent} = Agent.start_link(fn -> nil end)
    {:ok, calls_agent} = Agent.start_link(fn -> 0 end)

    updated_at = DateTime.add(DateTime.utc_now(), -120, :second)

    row = %Entry{
      key: "keyvalue:acme:ios:cas",
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "cas",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      source_node: "node-a",
      source_updated_at: updated_at,
      last_accessed_at: updated_at,
      updated_at: updated_at,
      deleted_at: nil
    }

    stub(KeyValueEntries, :distributed_watermark, fn -> Agent.get(watermark_agent, & &1) end)
    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    stub(KeyValueEntries, :materialize_remote_entry, fn attrs ->
      assert attrs.key == row.key
      send(parent, :materialized)
      :payload_updated
    end)

    stub(KeyValueEntries, :put_distributed_watermark, fn ^updated_at, key ->
      assert key == row.key
      Agent.update(watermark_agent, fn _ -> %{updated_at_value: updated_at, key_value: key} end)
      send(parent, :watermark_updated)
      :ok
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)

    stub(Repo, :all, fn _query, _opts ->
      Agent.get_and_update(calls_agent, fn count ->
        next_count = count + 1

        result =
          case next_count do
            1 -> [row]
            2 -> [row]
            _ -> []
          end

        {result, next_count}
      end)
    end)

    stub(Repo, :one, fn _query, _opts -> row end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :materialized
    assert_receive :watermark_updated
  end

  test "throttles local store size measurement across repeated polls" do
    parent = self()
    original_interval = Application.get_env(:cache, :distributed_kv_sync_interval_ms)

    Application.put_env(:cache, :distributed_kv_sync_interval_ms, 60_000)

    on_exit(fn ->
      Application.put_env(:cache, :distributed_kv_sync_interval_ms, original_interval)
    end)

    stub(KeyValueEntries, :distributed_watermark, fn -> %{updated_at_value: ~U[1970-01-01 00:00:00Z], key_value: ""} end)

    stub(KeyValueEntries, :estimated_size_bytes, fn ->
      send(parent, :size_measured)
      0
    end)

    stub(Repo, :all, fn _query, _opts -> [] end)

    start_supervised!(KeyValueReplicationPoller)
    assert_receive :size_measured, 10_000

    assert :ok = KeyValueReplicationPoller.poll_now()
    assert :ok = KeyValueReplicationPoller.poll_now()

    refute_receive :size_measured, 200
  end
end
