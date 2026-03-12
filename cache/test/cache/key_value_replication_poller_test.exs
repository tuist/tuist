defmodule Cache.KeyValueReplicationPollerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.DistributedKV.Entry, as: DistributedEntry
  alias Cache.DistributedKV.Repo, as: DistributedRepo
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

  test "poller materializes alive rows and advances watermark" do
    parent = self()
    {:ok, watermark_agent} = Agent.start_link(fn -> nil end)
    {:ok, calls_agent} = Agent.start_link(fn -> 0 end)

    updated_at = DateTime.add(DateTime.utc_now(), -120, :second)

    row = %DistributedEntry{
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

    stub(DistributedRepo, :all, fn _query, _opts ->
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

    stub(DistributedRepo, :one, fn _query, _opts -> row end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :materialized
    assert_receive :watermark_updated
  end
end
