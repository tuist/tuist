defmodule Cache.KeyValueReplicationPollerTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Config
  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Entry
  alias Cache.DistributedKV.Repo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueReplicationPoller
  alias Cache.KeyValueRepo
  alias Ecto.Adapters.SQL

  setup :set_mimic_from_context

  setup_all do
    ensure_distributed_repo_storage!()

    case start_supervised(Repo) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {:ok, _, _} = Ecto.Migrator.with_repo(Repo, &Ecto.Migrator.run(&1, :up, all: true))

    :ok
  end

  setup do
    :ok = Cache.KeyValueRepoTestHelpers.reset!()
    {:ok, _} = Cachex.clear(:cache_keyvalue_store)

    stub(Config, :key_value_mode, fn -> :distributed end)
    stub(Config, :distributed_kv_enabled?, fn -> true end)
    stub(Config, :distributed_kv_node_name, fn -> "test-node" end)
    stub(Config, :distributed_kv_sync_interval_ms, fn -> 60_000 end)
    stub(Cleanup, :published_cleanup_barriers_for_projects, fn _scope_pairs -> %{} end)
    :ok
  end

  test "poll_now drains multiple full pages before returning" do
    parent = self()

    {:ok, watermark_agent} =
      Agent.start_link(fn -> %{watermark_updated_at: ~U[1970-01-01 00:00:00Z], watermark_key: ""} end)

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
        %{watermark_updated_at: last_processed_row.updated_at, watermark_key: last_processed_row.key}
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

    {:ok, watermark_agent} =
      Agent.start_link(fn -> %{watermark_updated_at: ~U[1970-01-01 00:00:00Z], watermark_key: ""} end)

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
      Agent.update(watermark_agent, fn _ -> %{watermark_updated_at: updated_at, watermark_key: row.key} end)
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

  test "poller uses shared database time for lag filtering" do
    parent = self()

    stub(KeyValueEntries, :distributed_watermark, fn ->
      %{watermark_updated_at: ~U[1970-01-01 00:00:00Z], watermark_key: ""}
    end)

    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    expect(Repo, :all, fn %Ecto.Query{} = query, _opts ->
      {sql, _params} = SQL.to_sql(:all, Repo, query)
      assert sql =~ "clock_timestamp()"
      assert sql =~ "1 millisecond"
      send(parent, :poll_query_seen)
      []
    end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :poll_query_seen, 10_000
  end

  test "advances the watermark when an entire fetched page is filtered by published cleanup barriers" do
    parent = self()

    {:ok, watermark_agent} =
      Agent.start_link(fn -> %{watermark_updated_at: ~U[1970-01-01 00:00:00Z], watermark_key: ""} end)

    {:ok, calls_agent} = Agent.start_link(fn -> 0 end)

    base_time = DateTime.add(DateTime.utc_now(), -120, :second)

    row = %Entry{
      key: "keyvalue:acme:ios:filtered",
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "filtered",
      json_payload: Jason.encode!(%{entries: []}),
      source_node: "node-a",
      source_updated_at: base_time,
      last_accessed_at: base_time,
      updated_at: base_time,
      deleted_at: nil
    }

    row_key = row.key
    row_updated_at = row.updated_at

    stub(KeyValueEntries, :distributed_watermark, fn -> Agent.get(watermark_agent, & &1) end)
    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    stub(Cleanup, :published_cleanup_barriers_for_projects, fn _scope_pairs ->
      %{{"acme", "ios"} => row.source_updated_at}
    end)

    stub(KeyValueEntries, :put_distributed_watermark, fn updated_at, key ->
      Agent.update(watermark_agent, fn _ -> %{watermark_updated_at: updated_at, watermark_key: key} end)
      send(parent, {:watermark_advanced, key})
      :ok
    end)

    stub(Repo, :all, fn _query, _opts ->
      Agent.get_and_update(calls_agent, fn count ->
        next_count = count + 1
        result = if next_count == 1, do: [row], else: []
        {result, next_count}
      end)
    end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive {:watermark_advanced, ^row_key}, 10_000
    assert %{watermark_updated_at: ^row_updated_at, watermark_key: ^row_key} = Agent.get(watermark_agent, & &1)
    assert Agent.get(calls_agent, & &1) == 1
  end

  test "throttles local store size measurement across repeated polls" do
    parent = self()

    stub(KeyValueEntries, :distributed_watermark, fn ->
      %{watermark_updated_at: ~U[1970-01-01 00:00:00Z], watermark_key: ""}
    end)

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

    {:ok, watermark_agent} =
      Agent.start_link(fn -> %{watermark_updated_at: ~U[1970-01-01 00:00:00Z], watermark_key: ""} end)

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
        %{watermark_updated_at: last_processed_row.updated_at, watermark_key: last_processed_row.key}
      end)

      send(parent, {:watermark_updated, last_processed_row.key})
      :ok
    end)

    stub(KeyValueEntries, :put_distributed_watermark, fn updated_at, key ->
      Agent.update(watermark_agent, fn _ -> %{watermark_updated_at: updated_at, watermark_key: key} end)
      send(parent, {:watermark_updated, key})
      :ok
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)

    stub(Repo, :all, fn _query, _opts -> rows end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :first_chunk_applied, 10_000
    assert_receive {:watermark_updated, ^last_committed_key}, 10_000

    assert %{watermark_updated_at: ^last_committed_updated_at, watermark_key: ^last_committed_key} =
             Agent.get(watermark_agent, & &1)

    assert Process.whereis(KeyValueReplicationPoller)
  end

  test "initializes the watermark from the latest shared row and skips historical entries" do
    parent = self()
    updated_at = DateTime.add(DateTime.utc_now(), -120, :second)

    row = %Entry{
      key: "keyvalue:acme:ios:existing",
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "existing",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      source_node: "node-a",
      source_updated_at: updated_at,
      last_accessed_at: updated_at,
      updated_at: updated_at,
      deleted_at: nil
    }

    stub(KeyValueEntries, :distributed_watermark, fn -> nil end)
    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    stub(KeyValueEntries, :put_distributed_watermark, fn watermark_updated_at, watermark_key ->
      assert watermark_updated_at == row.updated_at
      assert watermark_key == row.key
      send(parent, :watermark_initialized)
      :ok
    end)

    stub(KeyValueEntries, :apply_remote_batch, fn _rows ->
      send(parent, :historical_row_applied)
      {:ok, batch_result([row])}
    end)

    stub(Repo, :one, fn _query, _opts -> row end)

    stub(Repo, :all, fn _query, _opts ->
      send(parent, :steady_state_query)
      []
    end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :watermark_initialized, 10_000
    assert_receive :steady_state_query, 10_000
    refute_receive :historical_row_applied, 200
  end

  test "initial watermark still syncs rows created after initialization" do
    parent = self()
    {:ok, repo_calls_agent} = Agent.start_link(fn -> 0 end)
    base_time = DateTime.add(DateTime.utc_now(), -300, :second)

    latest_row = %Entry{
      key: "keyvalue:acme:ios:existing",
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "existing",
      json_payload: Jason.encode!(%{entries: [%{"value" => "existing-artifact"}]}),
      source_node: "node-a",
      source_updated_at: base_time,
      last_accessed_at: base_time,
      updated_at: base_time,
      deleted_at: nil
    }

    new_row_updated_at = DateTime.add(base_time, 1, :second)

    new_row = %Entry{
      key: "keyvalue:acme:ios:new",
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "new",
      json_payload: Jason.encode!(%{entries: [%{"value" => "new-artifact"}]}),
      source_node: "node-a",
      source_updated_at: new_row_updated_at,
      last_accessed_at: new_row_updated_at,
      updated_at: new_row_updated_at,
      deleted_at: nil
    }

    stub(KeyValueEntries, :distributed_watermark, fn -> nil end)
    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    stub(KeyValueEntries, :put_distributed_watermark, fn updated_at, key ->
      assert updated_at == latest_row.updated_at
      assert key == latest_row.key
      send(parent, :watermark_initialized)
      :ok
    end)

    stub(KeyValueEntries, :apply_remote_batch, fn [row] ->
      assert row.key == new_row.key
      send(parent, :new_row_applied)
      {:ok, batch_result([row])}
    end)

    stub(KeyValueEntries, :commit_remote_batch, fn last_processed_row ->
      assert last_processed_row.updated_at == new_row.updated_at
      assert last_processed_row.key == new_row.key
      send(parent, :new_row_committed)
      :ok
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)
    stub(Repo, :one, fn _query, _opts -> latest_row end)

    stub(Repo, :all, fn _query, _opts ->
      Agent.get_and_update(repo_calls_agent, fn count ->
        next_count = count + 1

        result =
          case next_count do
            1 -> [new_row]
            _ -> []
          end

        {result, next_count}
      end)
    end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :watermark_initialized, 10_000
    assert_receive :new_row_applied, 10_000
    assert_receive :new_row_committed, 10_000
    assert 1 == Agent.get(repo_calls_agent, & &1)
  end

  @tag capture_log: true
  test "returns an error when steady-state remote batch apply fails unexpectedly" do
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

    stub(KeyValueEntries, :distributed_watermark, fn ->
      %{watermark_updated_at: ~U[1970-01-01 00:00:00Z], watermark_key: ""}
    end)

    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)
    stub(KeyValueEntries, :apply_remote_batch, fn [_row] -> {:error, :unexpected_failure} end)
    stub(Repo, :all, fn _query, _opts -> [row] end)

    pid = start_supervised!(KeyValueReplicationPoller)

    assert {:error, {:remote_batch_apply_failed, :unexpected_failure}} = KeyValueReplicationPoller.poll_now()
    assert Process.alive?(pid)
  end

  test "without an existing cutoff, the first shared rows still sync normally" do
    parent = self()
    updated_at = DateTime.add(DateTime.utc_now(), -120, :second)

    row = %Entry{
      key: "keyvalue:acme:ios:first",
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "first",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      source_node: "node-a",
      source_updated_at: updated_at,
      last_accessed_at: updated_at,
      updated_at: updated_at,
      deleted_at: nil
    }

    stub(KeyValueEntries, :distributed_watermark, fn -> nil end)
    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    stub(KeyValueEntries, :put_distributed_watermark, fn _updated_at, _key ->
      send(parent, :watermark_initialized)
      :ok
    end)

    stub(KeyValueEntries, :apply_remote_batch, fn [batch_row] ->
      assert batch_row.key == row.key
      send(parent, :first_row_applied)
      {:ok, batch_result([batch_row])}
    end)

    stub(KeyValueEntries, :commit_remote_batch, fn last_processed_row ->
      assert last_processed_row.updated_at == row.updated_at
      assert last_processed_row.key == row.key
      send(parent, :first_row_committed)
      :ok
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)
    stub(Repo, :one, fn _query, _opts -> nil end)

    stub(Repo, :all, fn _query, _opts ->
      send(parent, :steady_state_query)
      [row]
    end)

    start_supervised!(KeyValueReplicationPoller)

    assert_receive :steady_state_query, 10_000
    refute_receive :watermark_initialized, 200
    assert_receive :first_row_applied, 10_000
    assert_receive :first_row_committed, 10_000
  end

  @tag capture_log: true
  test "survives post-commit invalidation failures and eventually clears stale cache entries" do
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

      assert_receive {:cache_del_failed, 1, ^pid_1}, 10_000

      assert {:error, %RuntimeError{message: "boom"}} = KeyValueReplicationPoller.poll_now()
      assert_receive {:cache_del_failed, 2, ^pid_1}, 10_000

      assert :ok = KeyValueReplicationPoller.poll_now()
      assert_receive {:cache_del_succeeded, 3, ^pid_1}, 10_000

      assert Process.alive?(pid_1)

      assert %{watermark_updated_at: ^updated_at, watermark_key: ^row_key} = KeyValueEntries.distributed_watermark()

      assert {:ok, nil} = Cachex.get(:cache_keyvalue_store, row_key)

      record = KeyValueRepo.get_by!(KeyValueEntry, key: row_key)
      assert Jason.decode!(record.json_payload)["entries"] == [%{"value" => "artifact"}]
    end)
  end

  test "persists watermark advancement for a full page filtered by published barriers" do
    parent = self()
    {:ok, repo_calls_agent} = Agent.start_link(fn -> 0 end)

    base_time = DateTime.add(DateTime.utc_now(), -2_000, :second)

    filtered_rows =
      Enum.map(1..1000, fn i ->
        updated_at = DateTime.add(base_time, i, :second)

        %Entry{
          key: "keyvalue:acme:ios:filtered-#{i}",
          account_handle: "acme",
          project_handle: "ios",
          cas_id: "filtered-#{i}",
          json_payload: Jason.encode!(%{entries: []}),
          source_node: "node-a",
          source_updated_at: updated_at,
          last_accessed_at: updated_at,
          updated_at: updated_at,
          deleted_at: nil
        }
      end)

    barrier =
      filtered_rows
      |> List.last()
      |> Map.fetch!(:source_updated_at)
      |> DateTime.truncate(:second)
      |> DateTime.add(1, :second)

    stub(Cleanup, :published_cleanup_barriers_for_projects, fn _scope_pairs ->
      %{{"acme", "ios"} => barrier}
    end)

    :ok = KeyValueEntries.put_distributed_watermark(~U[1970-01-01 00:00:00Z], "")

    stub(KeyValueEntries, :estimated_size_bytes, fn ->
      send(parent, :poll_complete)
      0
    end)

    stub(KeyValueEntries, :apply_remote_batch, fn rows ->
      flunk("did not expect to apply filtered rows: #{inspect(Enum.map(rows, & &1.key))}")
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)

    stub(Repo, :all, fn _query, _opts ->
      Agent.get_and_update(repo_calls_agent, fn count ->
        next_count = count + 1

        result =
          case next_count do
            1 -> filtered_rows
            _ -> []
          end

        {result, next_count}
      end)
    end)

    start_supervised!(KeyValueReplicationPoller)
    assert_receive :poll_complete, 10_000

    filtered_last_key = "keyvalue:acme:ios:filtered-1000"
    filtered_last_updated_at = List.last(filtered_rows).updated_at

    assert_eventually(fn ->
      match?(
        %{watermark_updated_at: ^filtered_last_updated_at, watermark_key: ^filtered_last_key},
        KeyValueEntries.distributed_watermark()
      )
    end)

    assert 2 == Agent.get(repo_calls_agent, & &1)

    assert :ok = KeyValueReplicationPoller.poll_now()

    assert 3 == Agent.get(repo_calls_agent, & &1)

    assert match?(
             %{watermark_updated_at: ^filtered_last_updated_at, watermark_key: ^filtered_last_key},
             KeyValueEntries.distributed_watermark()
           )
  end

  test "advances across a full filtered page and keeps draining later pages" do
    parent = self()
    {:ok, repo_calls_agent} = Agent.start_link(fn -> 0 end)

    base_time = DateTime.add(DateTime.utc_now(), -2_000, :second)

    filtered_rows =
      Enum.map(1..1000, fn i ->
        updated_at = DateTime.add(base_time, i, :second)

        %Entry{
          key: "keyvalue:acme:ios:filtered-#{i}",
          account_handle: "acme",
          project_handle: "ios",
          cas_id: "filtered-#{i}",
          json_payload: Jason.encode!(%{entries: []}),
          source_node: "node-a",
          source_updated_at: updated_at,
          last_accessed_at: updated_at,
          updated_at: updated_at,
          deleted_at: nil
        }
      end)

    barrier =
      filtered_rows
      |> List.last()
      |> Map.fetch!(:source_updated_at)
      |> DateTime.truncate(:second)
      |> DateTime.add(1, :second)

    next_updated_at = DateTime.add(barrier, 1, :second)

    next_row = %Entry{
      key: "keyvalue:acme:ios:live",
      account_handle: "acme",
      project_handle: "ios",
      cas_id: "live",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      source_node: "node-a",
      source_updated_at: next_updated_at,
      last_accessed_at: next_updated_at,
      updated_at: next_updated_at,
      deleted_at: nil
    }

    stub(Cleanup, :published_cleanup_barriers_for_projects, fn _scope_pairs ->
      %{{"acme", "ios"} => barrier}
    end)

    :ok = KeyValueEntries.put_distributed_watermark(~U[1970-01-01 00:00:00Z], "")
    stub(KeyValueEntries, :estimated_size_bytes, fn -> 0 end)

    stub(KeyValueEntries, :apply_remote_batch, fn [row] ->
      assert row.key == next_row.key
      send(parent, :live_row_applied)
      {:ok, batch_result([row])}
    end)

    stub(KeyValueEntries, :commit_remote_batch, fn last_processed_row ->
      :ok = KeyValueEntries.put_distributed_watermark(last_processed_row.updated_at, last_processed_row.key)
      send(parent, :live_row_committed)
      :ok
    end)

    stub(KeyValueAccessTracker, :mark_shared_lineage, fn _key -> :ok end)

    stub(Repo, :all, fn _query, _opts ->
      Agent.get_and_update(repo_calls_agent, fn count ->
        next_count = count + 1

        result =
          case next_count do
            1 -> filtered_rows
            2 -> [next_row]
            _ -> []
          end

        {result, next_count}
      end)
    end)

    start_supervised!(KeyValueReplicationPoller)
    assert_receive :live_row_applied, 10_000
    assert_receive :live_row_committed, 10_000

    assert 2 == Agent.get(repo_calls_agent, & &1)
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

  defp ensure_distributed_repo_storage! do
    case Repo.__adapter__().storage_up(Repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> raise "failed to create distributed KV test database: #{inspect(reason)}"
    end
  end
end
