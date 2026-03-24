defmodule Cache.KeyValueReplicationPollerTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Config
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Repo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueReplicationPoller
  alias Cache.KeyValueRepo
  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup do
    :ok = Sandbox.checkout(KeyValueRepo)
    Sandbox.mode(KeyValueRepo, {:shared, self()})
    {:ok, _} = Cachex.clear(:cache_keyvalue_store)

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

    stub(KeyValueEntries, :commit_remote_batch, fn last_processed_row ->
      Agent.update(watermark_agent, fn _ ->
        %{updated_at_value: last_processed_row.updated_at, key_value: last_processed_row.key}
      end)

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

    stub(KeyValueEntries, :commit_remote_batch, fn last_processed_row ->
      assert last_processed_row.updated_at == updated_at
      assert last_processed_row.key == row.key
      Agent.update(watermark_agent, fn _ -> %{updated_at_value: updated_at, key_value: row.key} end)
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

    stub(KeyValueEntries, :commit_remote_batch, fn last_processed_row ->
      Agent.update(watermark_agent, fn _ ->
        %{updated_at_value: last_processed_row.updated_at, key_value: last_processed_row.key}
      end)

      send(parent, {:watermark_updated, last_processed_row.key})
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

  test "does not advance the bootstrap watermark when bootstrap stops on a busy local store" do
    parent = self()
    {:ok, repo_calls_agent} = Agent.start_link(fn -> 0 end)
    updated_at = DateTime.add(DateTime.utc_now(), -120, :second)

    row = %Entry{
      key: "keyvalue:acme:ios:bootstrap",
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "bootstrap",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      source_node: "node-a",
      source_updated_at: updated_at,
      last_accessed_at: updated_at,
      updated_at: updated_at,
      deleted_at: nil
    }

    stub(KeyValueEntries, :distributed_watermark, fn -> nil end)
    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    stub(KeyValueEntries, :materialize_remote_entries, fn rows ->
      assert Enum.map(rows, & &1.key) == [row.key]
      send(parent, {:bootstrap_attempted, row.key})
      {:error, :busy}
    end)

    stub(KeyValueEntries, :put_distributed_watermark, fn _updated_at, _key ->
      send(parent, :watermark_advanced)
      :ok
    end)

    stub(KeyValueEntries, :apply_remote_batch, fn _rows ->
      send(parent, :steady_state_polled)
      {:ok, batch_result([row])}
    end)

    stub(Repo, :one, fn _query, _opts -> row end)

    stub(Repo, :all, fn _query, _opts ->
      Agent.get_and_update(repo_calls_agent, fn count ->
        next_count = count + 1
        result = if next_count == 1, do: [row], else: []
        {result, next_count}
      end)
    end)

    start_supervised!(KeyValueReplicationPoller)

    row_key = row.key
    assert_receive {:bootstrap_attempted, ^row_key}, 10_000
    refute_receive :watermark_advanced, 200
    refute_receive :steady_state_polled, 200
    assert Agent.get(repo_calls_agent, & &1) == 1
  end

  test "bootstrap materializes rows in chunked local transactions" do
    parent = self()
    {:ok, repo_calls_agent} = Agent.start_link(fn -> 0 end)
    base_time = DateTime.add(DateTime.utc_now(), -300, :second)

    rows =
      Enum.map(1..150, fn i ->
        updated_at = DateTime.add(base_time, i, :second)

        %Entry{
          key: "keyvalue:acme:ios:bootstrap-#{i}",
          account_handle: "acme",
          project_handle: "ios",
          cas_id: "bootstrap-#{i}",
          json_payload: Jason.encode!(%{entries: [%{"value" => "artifact-#{i}"}]}),
          source_node: "node-a",
          source_updated_at: updated_at,
          last_accessed_at: updated_at,
          updated_at: updated_at,
          deleted_at: nil
        }
      end)

    latest_row = List.last(rows)

    stub(KeyValueEntries, :distributed_watermark, fn -> nil end)
    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    stub(KeyValueEntries, :materialize_remote_entries, fn chunk ->
      send(parent, {:bootstrap_batch_size, length(chunk)})

      {:ok,
       %{
         inserted_count: length(chunk),
         payload_updated_count: 0,
         access_updated_count: 0,
         invalidate_keys: Enum.map(chunk, & &1.key)
       }}
    end)

    stub(KeyValueEntries, :put_distributed_watermark, fn updated_at, key ->
      assert updated_at == latest_row.updated_at
      assert key == latest_row.key
      send(parent, :bootstrap_watermark_advanced)
      :ok
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)
    stub(Repo, :one, fn _query, _opts -> latest_row end)

    stub(Repo, :all, fn _query, _opts ->
      Agent.get_and_update(repo_calls_agent, fn count ->
        next_count = count + 1

        result =
          case next_count do
            1 -> rows
            _ -> []
          end

        {result, next_count}
      end)
    end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive {:bootstrap_batch_size, 100}, 10_000
    assert_receive {:bootstrap_batch_size, 50}, 10_000
    assert_receive :bootstrap_watermark_advanced, 10_000
  end

  @tag capture_log: true
  test "crashes on repeated post-commit invalidation failures and eventually clears stale cache entries" do
    capture_log(fn ->
      parent = self()
      :ok = KeyValueEntries.put_distributed_watermark(~U[1970-01-01 00:00:00Z], "")
      {:ok, repo_calls_agent} = Agent.start_link(fn -> 0 end)
      {:ok, cache_del_attempts_agent} = Agent.start_link(fn -> 0 end)

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

      stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)
      row_key = row.key
      {:ok, _} = Cachex.put(:cache_keyvalue_store, row_key, Jason.encode!(%{entries: [%{"value" => "stale"}]}))

      stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)
      stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)

      stub(Cachex, :del, fn :cache_keyvalue_store, key ->
        poller_pid = self()

        attempt =
          Agent.get_and_update(cache_del_attempts_agent, fn count ->
            next_count = count + 1
            {next_count, next_count}
          end)

        if attempt < 3 do
          send(parent, {:cache_del_failed, attempt, poller_pid})
          raise "boom"
        else
          send(parent, {:cache_del_succeeded, attempt, poller_pid})
          call_original(Cachex, :del, [:cache_keyvalue_store, key])
        end
      end)

      stub(Repo, :all, fn _query, _opts ->
        Agent.get_and_update(repo_calls_agent, fn count ->
          next_count = count + 1
          result = if next_count <= 3, do: [row], else: []
          {result, next_count}
        end)
      end)

      pid_1 = start_supervised!(KeyValueReplicationPoller)
      ref_1 = Process.monitor(pid_1)

      assert_receive {:cache_del_failed, 1, ^pid_1}, 10_000
      assert_receive {:DOWN, ^ref_1, :process, ^pid_1, _reason}, 10_000

      assert_receive {:cache_del_failed, 2, pid_2}, 10_000
      refute pid_2 == pid_1

      assert_eventually(fn -> not Process.alive?(pid_2) end)

      assert_receive {:cache_del_succeeded, 3, pid_3}, 10_000
      refute pid_3 in [pid_1, pid_2]

      assert_eventually(fn -> Process.whereis(KeyValueReplicationPoller) == pid_3 end)

      assert_eventually(fn ->
        match?(%{updated_at_value: ^updated_at, key_value: ^row_key}, KeyValueEntries.distributed_watermark())
      end)

      assert {:ok, nil} = Cachex.get(:cache_keyvalue_store, row_key)
      assert Process.alive?(pid_3)

      record = KeyValueRepo.get_by!(KeyValueEntry, key: row_key)
      assert Jason.decode!(record.json_payload)["entries"] == [%{"value" => "artifact"}]
    end)
  end

  defp assert_eventually(fun, attempts \\ 100)

  defp assert_eventually(_fun, 0) do
    flunk("expected condition to eventually become true")
  end

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
    end
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
