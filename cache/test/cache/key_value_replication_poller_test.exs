defmodule Cache.KeyValueReplicationPollerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.Config
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Repo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueReplicationPoller

  setup :set_mimic_from_context

  setup do
    stub(Config, :key_value_mode, fn -> :distributed end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)
    stub(Config, :distributed_kv_node_name, fn -> "test-node" end)
    stub(Config, :distributed_kv_sync_interval_ms, fn -> 60_000 end)
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

    stub(KeyValueEntries, :apply_remote_batch, fn rows ->
      materialized_count = Enum.count(rows, fn row -> is_nil(row.deleted_at) end)
      Agent.update(materialized_agent, &(&1 + materialized_count))
      {:ok, batch_result(rows)}
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
    assert total_watermark_puts == 22
    assert total_calls == 3
  end

  test "poller applies alive rows in chunks and advances watermark per committed chunk" do
    parent = self()
    {:ok, watermark_agent} = Agent.start_link(fn -> %{updated_at_value: ~U[1970-01-01 00:00:00Z], key_value: ""} end)
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

    stub(KeyValueEntries, :apply_remote_batch, fn [batch_row] ->
      assert batch_row.key == row.key
      send(parent, :chunk_applied)
      {:ok, batch_result([batch_row])}
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
        result = if next_count == 1, do: [row], else: []
        {result, next_count}
      end)
    end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :chunk_applied, 10_000
    assert_receive :watermark_updated, 10_000
  end

  test "throttles local store size measurement across repeated polls" do
    parent = self()

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

  test "stops the page early when local SQLite is busy and keeps the poller alive" do
    parent = self()
    {:ok, watermark_agent} = Agent.start_link(fn -> %{updated_at_value: ~U[1970-01-01 00:00:00Z], key_value: ""} end)

    base_time = DateTime.add(DateTime.utc_now(), -240, :second)

    rows =
      Enum.map(1..150, fn i ->
        updated_at = DateTime.add(base_time, i, :second)

        %Entry{
          key: "keyvalue:acme:ios:cas-#{i}",
          account_handle: "acme",
          project_handle: "ios",
          cas_id: "cas-#{i}",
          json_payload: Jason.encode!(%{entries: [%{"value" => "artifact-#{i}"}]}),
          source_node: "node-a",
          source_updated_at: updated_at,
          last_accessed_at: updated_at,
          updated_at: updated_at,
          deleted_at: nil
        }
      end)

    first_chunk = Enum.take(rows, 100)
    second_chunk = Enum.drop(rows, 100)
    last_committed_row = List.last(first_chunk)
    last_committed_key = last_committed_row.key
    last_committed_updated_at = last_committed_row.updated_at

    stub(KeyValueEntries, :distributed_watermark, fn -> Agent.get(watermark_agent, & &1) end)
    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    stub(KeyValueEntries, :apply_remote_batch, fn chunk ->
      cond do
        chunk == first_chunk ->
          send(parent, :first_chunk_applied)
          {:ok, batch_result(chunk)}

        chunk == second_chunk ->
          {:error, :busy}
      end
    end)

    stub(KeyValueEntries, :put_distributed_watermark, fn updated_at, key ->
      Agent.update(watermark_agent, fn _ -> %{updated_at_value: updated_at, key_value: key} end)
      send(parent, {:watermark_updated, key})
      :ok
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)

    stub(Repo, :all, fn _query, _opts -> rows end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :first_chunk_applied, 10_000
    assert_receive {:watermark_updated, ^last_committed_key}, 10_000

    assert %{updated_at_value: ^last_committed_updated_at, key_value: ^last_committed_key} =
             Agent.get(watermark_agent, & &1)

    assert Process.whereis(KeyValueReplicationPoller)
  end

  test "does not advance the watermark when post-commit side effects fail" do
    parent = self()
    sentinel_watermark = %{updated_at_value: ~U[1970-01-01 00:00:00Z], key_value: ""}
    {:ok, watermark_agent} = Agent.start_link(fn -> sentinel_watermark end)

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

    stub(KeyValueEntries, :apply_remote_batch, fn [batch_row] ->
      {:ok, batch_result([batch_row], %{mark_lineage_keys: [batch_row.key]})}
    end)

    stub(KeyValueEntries, :put_distributed_watermark, fn updated_at, key ->
      Agent.update(watermark_agent, fn _ -> %{updated_at_value: updated_at, key_value: key} end)
      send(parent, :watermark_updated)
      :ok
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key ->
      send(parent, :lineage_attempted)
      raise "boom"
    end)

    stub(Repo, :all, fn _query, _opts -> [row] end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :lineage_attempted, 10_000
    refute_receive :watermark_updated, 200
    assert Agent.get(watermark_agent, & &1) == sentinel_watermark
    assert Process.whereis(KeyValueReplicationPoller)
  end

  defp batch_result(rows, overrides \\ %{}) do
    alive_rows = Enum.filter(rows, &is_nil(&1.deleted_at))
    deleted_rows = Enum.reject(rows, &is_nil(&1.deleted_at))

    Map.merge(
      %{
        processed_count: length(rows),
        inserted_count: 0,
        payload_updated_count: length(alive_rows),
        access_updated_count: 0,
        deleted_count: length(deleted_rows),
        last_processed_row: List.last(rows),
        invalidate_keys: [],
        mark_lineage_keys: Enum.map(alive_rows, & &1.key),
        clear_lineage_keys: Enum.map(deleted_rows, & &1.key)
      },
      overrides
    )
  end
end
