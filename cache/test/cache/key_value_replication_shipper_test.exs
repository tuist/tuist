defmodule Cache.KeyValueReplicationShipperTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.DistributedKV.Cleanup
  alias Cache.DistributedKV.Repo, as: DistributedRepo
  alias Cache.KeyValueAccessTracker
  alias Cache.KeyValueEntries
  alias Cache.KeyValueEntry
  alias Cache.KeyValueReplicationShipper

  setup :set_mimic_from_context

  setup do
    Application.put_env(:cache, :key_value_mode, :distributed)
    Application.put_env(:cache, :distributed_kv_node_name, "test-node")
    on_exit(fn -> Application.put_env(:cache, :key_value_mode, :local) end)
    :ok
  end

  test "ships pending rows and clears the shipped token" do
    parent = self()
    token = DateTime.utc_now()
    json_payload = Jason.encode!(%{entries: [%{"value" => "artifact"}]})

    pending_entry = %KeyValueEntry{
      key: "keyvalue:acme:ios:cas",
      json_payload: json_payload,
      last_accessed_at: token,
      source_updated_at: token,
      replication_enqueued_at: token
    }

    stub(Cleanup, :latest_project_cleanup_cutoffs, fn _scopes -> %{} end)
    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)

    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)

    stub(KeyValueEntries, :clear_replication_token, fn "keyvalue:acme:ios:cas", ^token ->
      send(parent, :token_cleared)
      1
    end)

    stub(DistributedRepo, :query!, fn sql, params, opts ->
      assert sql =~ "INSERT INTO kv_entries"
      assert sql =~ "ON CONFLICT (key) DO UPDATE"

      assert [
               ["keyvalue:acme:ios:cas"],
               ["acme"],
               ["ios"],
               ["cas"],
               [^json_payload],
               ["test-node"],
               [^token],
               [^token],
               [updated_at]
             ] = params

      assert %DateTime{} = updated_at
      assert opts[:timeout]
      send(parent, :upserted)
      %{num_rows: 1}
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :upserted
    assert_receive :token_cleared
  end

  test "batches shared repo work for one flush" do
    parent = self()
    token = DateTime.utc_now()

    pending_entries = [
      %KeyValueEntry{
        key: "keyvalue:acme:ios:cas-a",
        json_payload: Jason.encode!(%{entries: [%{"value" => "artifact-a"}]}),
        last_accessed_at: token,
        source_updated_at: token,
        replication_enqueued_at: token
      },
      %KeyValueEntry{
        key: "keyvalue:acme:ios:cas-b",
        json_payload: Jason.encode!(%{entries: [%{"value" => "artifact-b"}]}),
        last_accessed_at: token,
        source_updated_at: token,
        replication_enqueued_at: token
      }
    ]

    expect(Cleanup, :latest_project_cleanup_cutoffs, fn scopes ->
      assert Enum.map(scopes, &{&1.account_handle, &1.project_handle}) == [{"acme", "ios"}, {"acme", "ios"}]
      send(parent, :cutoffs_loaded)
      %{}
    end)

    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> pending_entries end)

    expect(KeyValueEntries, :clear_replication_token, 2, fn key, ^token ->
      assert key in ["keyvalue:acme:ios:cas-a", "keyvalue:acme:ios:cas-b"]
      send(parent, {:token_cleared, key})
      1
    end)

    expect(DistributedRepo, :query!, fn sql, params, opts ->
      assert sql =~ "FROM UNNEST"
      assert Enum.at(params, 0) == ["keyvalue:acme:ios:cas-a", "keyvalue:acme:ios:cas-b"]
      assert Enum.at(params, 3) == ["cas-a", "cas-b"]
      assert Enum.at(params, 5) == ["test-node", "test-node"]
      assert length(Enum.at(params, 8)) == 2
      assert opts[:timeout]
      send(parent, :upsert_batch)
      %{num_rows: 2}
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :cutoffs_loaded
    assert_receive :upsert_batch
    assert_receive {:token_cleared, _}
    assert_receive {:token_cleared, _}
  end

  test "reloads cleanup cutoffs on each flush" do
    parent = self()
    token = DateTime.utc_now()
    original_interval = Application.get_env(:cache, :distributed_kv_ship_interval_ms)

    Application.put_env(:cache, :distributed_kv_ship_interval_ms, 60_000)

    on_exit(fn ->
      Application.put_env(:cache, :distributed_kv_ship_interval_ms, original_interval)
    end)

    pending_entry = %KeyValueEntry{
      key: "keyvalue:acme:ios:cas",
      json_payload: Jason.encode!(%{entries: [%{"value" => "artifact"}]}),
      last_accessed_at: token,
      source_updated_at: token,
      replication_enqueued_at: token
    }

    expect(Cleanup, :latest_project_cleanup_cutoffs, 2, fn _scopes ->
      send(parent, :cutoffs_loaded)
      %{}
    end)

    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)
    stub(KeyValueEntries, :clear_replication_token, fn _key, _token -> 1 end)
    stub(DistributedRepo, :query!, fn _sql, _params, _opts -> %{num_rows: 1} end)

    start_supervised!(KeyValueReplicationShipper)
    assert_receive :cutoffs_loaded

    assert :ok = KeyValueReplicationShipper.flush_now()
    assert_receive :cutoffs_loaded
  end

  test "same-second cleanup cutoffs do not discard pending rows" do
    parent = self()
    entry_updated_at = ~U[2026-03-12 12:00:00.050000Z]
    cleanup_started_at = ~U[2026-03-12 12:00:00.900000Z]
    json_payload = Jason.encode!(%{entries: [%{"value" => "artifact"}]})

    pending_entry = %KeyValueEntry{
      key: "keyvalue:acme:ios:cas",
      json_payload: json_payload,
      last_accessed_at: entry_updated_at,
      source_updated_at: entry_updated_at,
      replication_enqueued_at: entry_updated_at
    }

    expect(Cleanup, :latest_project_cleanup_cutoffs, fn _scopes ->
      %{{"acme", "ios"} => cleanup_started_at}
    end)

    stub(KeyValueAccessTracker, :clear, fn _key -> :ok end)
    stub(KeyValueEntries, :list_pending_replication, fn -> [pending_entry] end)

    expect(KeyValueEntries, :clear_replication_token, fn "keyvalue:acme:ios:cas", ^entry_updated_at ->
      send(parent, :token_cleared)
      1
    end)

    expect(DistributedRepo, :query!, fn sql, params, _opts ->
      assert sql =~ "INSERT INTO kv_entries"
      assert Enum.at(params, 0) == ["keyvalue:acme:ios:cas"]
      send(parent, :upserted)
      %{num_rows: 1}
    end)

    start_supervised!(KeyValueReplicationShipper)

    assert_receive :upserted
    assert_receive :token_cleared
  end
end
